import Darwin
import Foundation
import SwiftUI

enum ProcCategory: String, CaseIterable, Identifiable {
    case ai = "AI Agents"
    case docker = "Docker / VMs"
    case node = "Node / JS"
    case python = "Python"
    case server = "Servers"
    case other = "Other"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .ai: "sparkles"
        case .docker: "shippingbox.fill"
        case .node: "curlybraces"
        case .python: "chevron.left.forwardslash.chevron.right"
        case .server: "network"
        case .other: "gearshape"
        }
    }

    var color: Color {
        switch self {
        case .ai: .purple
        case .docker: .blue
        case .node: .green
        case .python: .yellow
        case .server: .orange
        case .other: .secondary
        }
    }
}

struct ProcInfo: Identifiable, Hashable {
    let pid: Int32
    let ppid: Int32
    let user: String
    let cpu: Double
    let rssKB: Int64
    let uptime: Int
    let command: String
    let name: String
    let executablePath: String?
    var category: ProcCategory = .other
    var ports: [Int] = []
    var cwd: String?

    var id: Int32 { pid }
    var memBytes: Int64 { rssKB * 1024 }
    var portsText: String { ports.map(String.init).joined(separator: ", ") }
    var cwdDisplay: String { cwd?.abbreviatingHome ?? "" }

    var uptimeText: String {
        let d = uptime / 86400, h = (uptime % 86400) / 3600, m = (uptime % 3600) / 60, s = uptime % 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m \(s)s" }
        return "\(s)s"
    }
}

enum ProcessScanner {
    private static let aiTokens: Set<String> = [
        "claude", "codex", "aider", "ollama", "gemini", "opencode", "goose", "openhands", "cursor-agent",
        "copilot-language-server", "llama-server", "lmstudio", "crush", "qwen", "chatgpt", "vllm",
        "mlx_lm", "cline", "kiro", "windsurf", "amazon-q", "q-agent", "devin", "plandex",
    ]
    private static let aiSubstrings = [
        "modelcontextprotocol", "mcp-server", "mcp_server", "@anthropic-ai", "@openai/codex", "claude-code",
        "lm studio", "@google/gemini-cli", "fastmcp", "mcp-remote", "@playwright/mcp", "langchain", "langgraph",
        "crewai", "autogen",
    ]
    private static let dockerTokens: Set<String> = [
        "docker", "dockerd", "containerd", "containerd-shim", "vpnkit", "colima", "limactl", "lima", "orbstack",
        "podman", "qemu-system-aarch64", "qemu-system-x86_64", "krunvm", "rancher", "nerdctl", "buildkitd",
        "utm", "multipass", "vfkit", "gvproxy",
    ]
    private static let nodeExecs: Set<String> = [
        "node", "bun", "deno", "npm", "npx", "pnpm", "yarn", "tsx", "ts-node", "nodemon", "pm2", "esbuild",
        "turbo", "vite", "next-server",
    ]
    private static let pythonExecs: Set<String> = ["uvicorn", "gunicorn", "jupyter", "celery", "flask", "hypercorn", "uv"]

    static func scan() -> [ProcInfo] {
        let output = Shell.run("/bin/ps", ["-axww", "-o", "pid=,ppid=,user=,%cpu=,rss=,etime=,command="])
        let me = getpid()
        var procs: [ProcInfo] = []

        for line in output.stdout.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 6, omittingEmptySubsequences: true)
            guard parts.count == 7, let pid = Int32(parts[0]), let ppid = Int32(parts[1]), pid != me else { continue }
            let command = String(parts[6])
            let execPath = executablePath(pid)
            let name = execPath.map { ($0 as NSString).lastPathComponent }
                ?? (String(command.split(separator: " ").first ?? "") as NSString).lastPathComponent
            procs.append(ProcInfo(
                pid: pid, ppid: ppid, user: String(parts[2]),
                cpu: Double(parts[3]) ?? 0, rssKB: Int64(parts[4]) ?? 0,
                uptime: parseElapsed(String(parts[5])), command: command, name: name,
                executablePath: execPath))
        }

        let ports = listeningPorts()
        for i in procs.indices {
            procs[i].ports = ports[procs[i].pid] ?? []
            procs[i].category = categorize(procs[i])
        }

        let interesting = procs.filter { $0.category != .other }.map(\.pid)
        let cwds = workingDirectories(interesting)
        for i in procs.indices { procs[i].cwd = cwds[procs[i].pid] }
        return procs
    }

    static func categorize(_ p: ProcInfo) -> ProcCategory {
        let cmd = p.command.lowercased()
        let name = p.name.lowercased()
        let tokens = Set(cmd.split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }).map(String.init))

        if aiTokens.contains(name) || !aiTokens.isDisjoint(with: tokens) || aiSubstrings.contains(where: cmd.contains) {
            return .ai
        }
        if dockerTokens.contains(name) || !dockerTokens.isDisjoint(with: tokens) || cmd.contains("com.docker.") {
            return .docker
        }
        if nodeExecs.contains(name) || cmd.contains("/node_modules/") { return .node }
        if name.hasPrefix("python") || pythonExecs.contains(name) { return .python }
        if !p.ports.isEmpty { return .server }
        return .other
    }

    /// `[[dd-]hh:]mm:ss` → seconds
    static func parseElapsed(_ s: String) -> Int {
        var days = 0
        var rest = Substring(s)
        if let dash = s.firstIndex(of: "-") {
            days = Int(s[..<dash]) ?? 0
            rest = s[s.index(after: dash)...]
        }
        let comps = rest.split(separator: ":").compactMap { Int($0) }
        var secs = 0
        for c in comps { secs = secs * 60 + c }
        return days * 86400 + secs
    }

    private static func executablePath(_ pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let len = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        return len > 0 ? String(cString: buffer) : nil
    }

    /// pid → listening TCP ports (only processes visible to the current user).
    static func listeningPorts() -> [Int32: [Int]] {
        let out = Shell.run("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpn"], timeout: 8)
        var result: [Int32: Set<Int>] = [:]
        var current: Int32?
        for line in out.stdout.split(separator: "\n") {
            if line.hasPrefix("p") {
                current = Int32(line.dropFirst())
            } else if line.hasPrefix("n"), let pid = current,
                      let colon = line.lastIndex(of: ":"), let port = Int(line[line.index(after: colon)...]) {
                result[pid, default: []].insert(port)
            }
        }
        return result.mapValues { $0.sorted() }
    }

    static func workingDirectories(_ pids: [Int32]) -> [Int32: String] {
        guard !pids.isEmpty else { return [:] }
        let list = pids.map(String.init).joined(separator: ",")
        let out = Shell.run("/usr/sbin/lsof", ["-a", "-d", "cwd", "-p", list, "-Fpn"], timeout: 8)
        var result: [Int32: String] = [:]
        var current: Int32?
        for line in out.stdout.split(separator: "\n") {
            if line.hasPrefix("p") {
                current = Int32(line.dropFirst())
            } else if line.hasPrefix("n"), let pid = current {
                result[pid] = String(line.dropFirst())
            }
        }
        return result
    }
}

enum ProcessKiller {
    private static let critical: Set<String> = [
        "launchd", "kernel_task", "WindowServer", "loginwindow", "logind", "opendirectoryd", "securityd",
        "coreservicesd", "Finder", "Dock", "SystemUIServer", "configd", "notifyd", "syslogd", "mds",
    ]

    static func isKillable(_ pid: Int32, in procs: [ProcInfo]) -> Bool {
        guard pid > 1, pid != getpid() else { return false }
        if let p = procs.first(where: { $0.pid == pid }), critical.contains(p.name) { return false }
        return true
    }

    /// Returns pids plus all descendants, children ordered before parents.
    static func withDescendants(_ roots: [Int32], in procs: [ProcInfo]) -> [Int32] {
        var children: [Int32: [Int32]] = [:]
        for p in procs { children[p.ppid, default: []].append(p.pid) }
        var ordered: [Int32] = []
        var visited = Set<Int32>()
        func visit(_ pid: Int32) {
            guard visited.insert(pid).inserted else { return }
            for c in children[pid] ?? [] { visit(c) }
            ordered.append(pid)
        }
        roots.forEach(visit)
        return ordered
    }

    /// Sends a signal; returns pids that need root.
    static func send(_ sig: Int32, to pids: [Int32]) -> [Int32] {
        var denied: [Int32] = []
        for pid in pids where Darwin.kill(pid, sig) != 0 && errno == EPERM {
            denied.append(pid)
        }
        return denied
    }

    static func isAlive(_ pid: Int32) -> Bool {
        Darwin.kill(pid, 0) == 0 || errno == EPERM
    }
}
