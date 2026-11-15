# HealthyMac

Native macOS (SwiftUI) utility:

- **Applications** – uninstall an app *and* everything it left around: caches, preferences (incl. ByHost),
  containers, group containers, saved state, logs, crash reports, HTTP storage, WebKit data, cookies,
  launch agents/daemons, privileged helper tools, plug-ins, installer receipts, `/var/folders` temp/cache.
  Drag any `.app` onto the list. Uncheck the app bundle to just *reset* an app (remove its data only).
- **Leftover Files** – data of apps that are no longer installed (bundle-id folders with no matching app,
  launch jobs pointing at missing programs). Nothing preselected.
- **Disk Scan** – one fast pass over your home folder, the whole disk or any folder. Finds
  regenerable folders (`node_modules`, `.next`, Rust `target`, Gradle/Flutter `build`, `Pods`, `.venv`,
  DerivedData, npm/pnpm/pip/Homebrew/Gradle caches, AI model stores…) with their age, files of 100 MB or more,
  and an explorer to drill into folders by size.
- **Processes** – live list of dev/AI processes, categorised: AI agents (Claude Code, Codex, Aider,
  Ollama, Gemini CLI, MCP servers…), Docker/VMs, Node/JS, Python, anything listening on a TCP port.
  Shows CPU, RAM, ports, uptime and the **project folder** (cwd). Terminate / force kill / kill whole tree.
- **Docker** – containers with CPU/RAM, compose project; stop / kill / restart / remove, stop a whole project.

## No helper tool

Nothing is installed as root, no `SMJobBless`/`SMAppService` daemon. When a file or process is owned by
root, HealthyMac asks once via the standard macOS administrator password prompt
(`do shell script … with administrator privileges`) and runs a single `rm -rf` / `kill` command.

Safety: a hard-coded guard refuses to delete system locations and well-known parent folders
(`/`, `/System`, `/Library`, `~/Library`, `~/Library/Caches`, `/Applications`, …), and apps on the sealed
system volume are marked protected. "Same vendor" matches are never preselected.

## Build & install

### Requirements

- macOS 14 (Sonoma) or newer
- Xcode or the Xcode Command Line Tools with a Swift 6 toolchain (`swift --version`)

### One-liner

Run from the project root:

```bash
./scripts/build-app.sh && cp -R build.noindex/HealthyMac.app /Applications/
```

The `&&` means the copy only runs if the build succeeded, so a failed build never
replaces a working install.

### What `./scripts/build-app.sh` does

1. `swift build -c release` – compiles an optimized binary with SwiftPM (no Xcode project needed).
2. Creates a fresh app bundle at `build.noindex/HealthyMac.app` (any previous one is deleted first).
   The `.noindex` suffix keeps Spotlight from showing this build copy as a second HealthyMac.app:
   ```
   build.noindex/HealthyMac.app/
     Contents/
       Info.plist            ← copied from Resources/Info.plist
       MacOS/HealthyMac      ← the release binary
       Resources/AppIcon.icns  (only if Resources/AppIcon.icns exists)
   ```
3. Code-signs the bundle with `codesign`. By default this is **ad-hoc** signing (`-`), which is
   enough to run locally but is not notarized.
4. Prints the bundle path and the install command.

### What `cp -R build.noindex/HealthyMac.app /Applications/` does

Copies the whole bundle (`-R` = recursive, an `.app` is a folder) into `/Applications`, so it
shows up in Launchpad and Spotlight and can be granted permissions in System Settings.
`/Applications` is normally writable by admin users, so no `sudo` is needed. Use
`~/Applications/` instead if you want a per-user install.

### Updating an existing install

`cp -R` merges into an existing `/Applications/HealthyMac.app` instead of replacing it, which
can leave stale files and break the code signature. For updates, quit the app and replace it
cleanly:

```bash
osascript -e 'quit app "HealthyMac"' 2>/dev/null
./scripts/build-app.sh && rm -rf /Applications/HealthyMac.app && cp -R build.noindex/HealthyMac.app /Applications/
```

(`ditto build.noindex/HealthyMac.app /Applications/HealthyMac.app` after the `rm -rf` works too.)

### Signing with your own identity (recommended)

macOS ties privacy permissions (Full Disk Access, App Management) to the app's signature.
With ad-hoc signing the signature changes on **every** rebuild, so macOS forgets the
permissions and you have to grant them again. Sign with a stable identity to avoid that:

```bash
security find-identity -v -p codesigning     # list available identities
SIGN_IDENTITY="Apple Development: Your Name (TEAMID)" ./scripts/build-app.sh \
  && cp -R build.noindex/HealthyMac.app /Applications/
```

A free Apple ID added in Xcode → Settings → Accounts is enough to get an "Apple Development"
certificate.

### First launch

- Open it from `/Applications` (or `open /Applications/HealthyMac.app`).
- Because the app is built locally, Gatekeeper normally lets it run. If you copied a build
  from another Mac and macOS blocks it, right-click → **Open**, or run
  `xattr -dr com.apple.quarantine /Applications/HealthyMac.app`.
- Then grant the permissions below.

### Troubleshooting

| Problem | Fix |
|---|---|
| `permission denied: ./scripts/build-app.sh` | `chmod +x scripts/build-app.sh` |
| `swift: command not found` / toolchain errors | `xcode-select --install`, or `sudo xcode-select -s /Applications/Xcode.app` |
| Permissions "lost" after a rebuild | Expected with ad-hoc signing: re-grant them, or use `SIGN_IDENTITY` |
| Old version still opens | Quit the app, then do the clean update shown above |

### Dev loop

```bash
swift run      # build + run without making a bundle (permissions attach to Terminal instead)
```

## Permissions (System Settings → Privacy & Security)

- **Full Disk Access** – to see/remove protected app data (containers, some caches).
- **App Management** – to delete other apps' bundles on macOS 13+.

Both have shortcut buttons in the app (sidebar banner and Settings ⌘,).

## Layout

```
Sources/HealthyMac/
  Core/          Shell (process runner + admin prompt), SafetyGuard, FileSize, Permissions
  DiskScan/      DiskScanner (fts walk, pruned size tree), JunkRules, DiskScanModel
  Uninstaller/   AppScanner, LeftoverFinder, OrphanFinder, Remover, UninstallerModel
  Processes/     ProcessScanner (ps + lsof + libproc), ProcessKiller, DockerClient, models
  Views/         SwiftUI views
```

## Documentation

How it works internally: [docs/](docs/README.md): architecture, leftover matching rules, process
categorisation and killing, privileges and safety, development notes.

## License

Proprietary. Copyright (c) 2026 Edvinas. All rights reserved.
The source is public for reference only: you may not use, copy, modify or distribute it without
written permission. See [LICENSE](LICENSE).
