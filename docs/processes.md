# Processes and Docker

## Scanning — `ProcessScanner.scan()`

One refresh (every 3 s while the Processes screen is visible) does:

1. **Process list:** `/bin/ps -axww -o pid=,ppid=,user=,%cpu=,rss=,etime=,command=`.
   Each line is split into at most 7 fields, so the full command line (with spaces) stays
   intact. `etime` (`[[dd-]hh:]mm:ss`) is converted to seconds.
2. **Executable name:** `proc_pidpath()` (libproc) gives the real executable path, which
   handles app paths with spaces. If that fails (other users' processes), the first word of the
   command is used.
3. **Listening ports:** `lsof -nP -iTCP -sTCP:LISTEN -Fpn` → map pid → ports.
4. **Categorise** every process (below).
5. **Working folder:** for categorised processes only, a single
   `lsof -a -d cwd -p <pid,pid,…> -Fpn`. This is how the Folder column shows *which project* a
   `node` or `python` process belongs to.

HealthyMac's own process is excluded. Processes owned by other users (root) show up, but
their ports and folders are only visible with root, so those columns may be empty.

## Categories — `ProcessScanner.categorize`

Checked in this order; the first match wins:

| Category | Matches when |
|---|---|
| **AI Agents** | executable name or any word of the command is one of `claude`, `codex`, `aider`, `ollama`, `gemini`, `opencode`, `goose`, `openhands`, `cursor-agent`, `copilot-language-server`, `llama-server`, `lmstudio`, `crush`, `qwen`, `chatgpt`, `vllm`, `mlx_lm`, `cline`, `kiro`, `windsurf`, `amazon-q`, …; or the command contains `modelcontextprotocol`, `mcp-server`, `@anthropic-ai`, `@openai/codex`, `claude-code`, `@google/gemini-cli`, `fastmcp`, `mcp-remote`, `langchain`, `langgraph`, `crewai`, `autogen`, … |
| **Docker / VMs** | `docker`, `dockerd`, `containerd`, `vpnkit`, `colima`, `lima`, `limactl`, `orbstack`, `podman`, `qemu-system-*`, `nerdctl`, `buildkitd`, `utm`, `multipass`, `vfkit`, `gvproxy`, or `com.docker.` in the command |
| **Node / JS** | executable `node`, `bun`, `deno`, `npm`, `npx`, `pnpm`, `yarn`, `tsx`, `ts-node`, `nodemon`, `pm2`, `esbuild`, `turbo`, `vite`, `next-server`, or `/node_modules/` in the command |
| **Python** | executable starts with `python`, or is `uvicorn`, `gunicorn`, `jupyter`, `celery`, `flask`, `hypercorn`, `uv` |
| **Servers** | anything else that listens on a TCP port |
| **Other** | everything else (shown only with the **All** filter) |

"Words" means the lowercased command split on anything that isn't a letter, digit, `-` or `_`.
So `/usr/local/bin/claude` and `node …/@anthropic-ai/claude-code/cli.js` both count as AI.
An AI agent running on Node counts as **AI**, not Node, because AI is checked first.

The lists live at the top of `ProcessScanner.swift`; add a word there to teach it a new tool.

## Filtering and sorting

`ProcessModel.visible` applies the segmented filter, then the search box (matches the command,
exact PID, port or folder), then the table's sort order (default: CPU descending). The filter
bar shows the total CPU and RAM of the current filter.

## Killing — `ProcessKiller` + `ProcessModel.perform`

| Action | Signal | Children |
|---|---|---|
| Terminate | `SIGTERM` (lets the process clean up) | no |
| Terminate with Children / Kill Tree | `SIGTERM` | yes |
| Force Kill (footer button) | `SIGKILL` | yes |
| Force Kill (menu) | `SIGKILL` | menu offers both |

- **Children:** built from the `ppid` of every process in the last scan, visited depth-first,
  so children are signalled **before** their parents and can't be re-spawned by them.
- **Protected:** pid 0/1, HealthyMac itself, and critical system processes (`launchd`,
  `WindowServer`, `loginwindow`, `Finder`, `Dock`, …) are skipped.
- **Root processes:** `kill()` returns `EPERM`. Those pids are collected and signalled with a
  single `/bin/kill -TERM|-KILL …` through the admin prompt.
- After `SIGTERM` the app waits 3 s and reports how many are still alive (`kill(pid, 0)`),
  suggesting Force Kill. It doesn't escalate on its own, because tools like Docker Desktop can
  need longer to shut down cleanly.

Every kill is confirmed in a dialog that lists the target names and PIDs.

## Docker — `DockerClient` + `DockerModel`

- **CLI discovery:** the first executable among `/usr/local/bin/docker`,
  `/opt/homebrew/bin/docker`, `~/.orbstack/bin/docker`, `~/.docker/bin/docker`,
  `~/.rd/bin/docker` and `Docker.app/Contents/Resources/bin/docker`. Works with Docker Desktop,
  OrbStack, Colima and Rancher Desktop (it uses whatever docker context is active).
- **List:** `docker ps [-a] --no-trunc --format '{{json .}}'`, one JSON object per line.
  The compose project comes from the `com.docker.compose.project` label.
- **Stats:** if anything is running, `docker stats --no-stream --format '{{json .}}'` adds
  CPU % and memory usage.
- **Actions:** `stop`, `kill`, `start`, `restart`, `rm -f`, plus "stop whole compose project"
  (stops every running container with the same project label).
- **Daemon down:** errors like "Cannot connect to the Docker daemon" show a **Start Docker**
  button that opens Docker Desktop / OrbStack / Rancher Desktop.
- GUI apps don't get your shell's `PATH`, so `Shell.run` sets an extended `PATH` (Homebrew,
  OrbStack, Docker, Rancher) for every command it starts.
