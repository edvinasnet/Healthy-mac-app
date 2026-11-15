import AppKit
import Observation

enum ProcFilter: String, CaseIterable, Identifiable {
    case dev = "Dev & AI"
    case ai = "AI"
    case docker = "Docker"
    case node = "Node"
    case python = "Python"
    case server = "Servers"
    case all = "All"

    var id: String { rawValue }

    func includes(_ c: ProcCategory) -> Bool {
        switch self {
        case .dev: c != .other
        case .ai: c == .ai
        case .docker: c == .docker
        case .node: c == .node
        case .python: c == .python
        case .server: c == .server
        case .all: true
        }
    }
}

struct KillRequest: Identifiable {
    let id = UUID()
    let pids: [Int32]
    let force: Bool
    let tree: Bool

    var title: String {
        let verb = force ? "Force kill" : "Terminate"
        return "\(verb) \(pids.count) process\(pids.count == 1 ? "" : "es")\(tree ? " and their children" : "")?"
    }
}

@MainActor
@Observable
final class ProcessModel {
    var processes: [ProcInfo] = []
    var filter: ProcFilter = .dev
    var search = ""
    var autoRefresh = true
    var isRefreshing = false
    var selection = Set<Int32>()
    var sortOrder = [KeyPathComparator(\ProcInfo.cpu, order: .reverse)]
    var status: String?
    private var loop: Task<Void, Never>?

    var visible: [ProcInfo] {
        processes
            .filter { filter.includes($0.category) }
            .filter {
                search.isEmpty || $0.command.localizedCaseInsensitiveContains(search)
                    || String($0.pid) == search || $0.portsText.contains(search)
                    || ($0.cwd?.localizedCaseInsensitiveContains(search) ?? false)
            }
            .sorted(using: sortOrder)
    }

    func count(_ f: ProcFilter) -> Int { processes.filter { f.includes($0.category) }.count }

    func totals(_ f: ProcFilter) -> (cpu: Double, mem: Int64) {
        let list = processes.filter { f.includes($0.category) }
        return (list.reduce(0) { $0 + $1.cpu }, list.reduce(0) { $0 + $1.memBytes })
    }

    func start() {
        guard loop == nil else { return }
        loop = Task {
            while !Task.isCancelled {
                if autoRefresh { await refresh() }
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        let list = await Task.detached { ProcessScanner.scan() }.value
        processes = list
        let alive = Set(list.map(\.pid))
        selection = selection.intersection(alive)
        isRefreshing = false
    }

    func perform(_ request: KillRequest) {
        let snapshot = processes
        Task {
            var targets = request.tree ? ProcessKiller.withDescendants(request.pids, in: snapshot) : request.pids
            targets = targets.filter { ProcessKiller.isKillable($0, in: snapshot) }
            guard !targets.isEmpty else {
                status = "Nothing to kill (protected system process?)"
                return
            }
            let sig = request.force ? SIGKILL : SIGTERM
            let denied = ProcessKiller.send(sig, to: targets)
            if !denied.isEmpty {
                do {
                    let flag = request.force ? "-KILL" : "-TERM"
                    try Shell.runAsAdmin("/bin/kill \(flag) " + denied.map(String.init).joined(separator: " "))
                } catch {
                    status = "Admin kill failed: \(error.localizedDescription)"
                }
            }
            status = "Sent \(request.force ? "SIGKILL" : "SIGTERM") to \(targets.count) process(es)…"
            try? await Task.sleep(for: .seconds(request.force ? 0.5 : 3))
            let survivors = targets.filter(ProcessKiller.isAlive)
            status = survivors.isEmpty
                ? "Stopped \(targets.count) process(es)."
                : "\(survivors.count) process(es) still running — use Force Kill."
            await refresh()
        }
    }
}

@MainActor
@Observable
final class DockerModel {
    var containers: [DockerContainer] = []
    var error: DockerError?
    var showStopped = false
    var isRefreshing = false
    var selection = Set<String>()
    var status: String?
    var loaded = false
    private var loop: Task<Void, Never>?

    var available: Bool { DockerClient.binary != nil }

    func start() {
        guard loop == nil else { return }
        loop = Task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
    }

    func refresh() async {
        guard !isRefreshing, available else { return }
        isRefreshing = true
        let all = showStopped
        let result = await Task.detached { DockerClient.list(all: all) }.value
        switch result {
        case .success(let list):
            containers = list
            error = nil
            selection = selection.intersection(Set(list.map(\.id)))
        case .failure(let e):
            containers = []
            error = e
        }
        loaded = true
        isRefreshing = false
    }

    func perform(_ action: DockerClient.Action, ids: [String]) {
        guard !ids.isEmpty else { return }
        status = "\(action.rawValue) \(ids.count) container(s)…"
        Task {
            let out = await Task.detached { DockerClient.perform(action, ids: ids) }.value
            status = out.ok ? "\(action.rawValue) done for \(ids.count) container(s)." : out.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            await refresh()
        }
    }

    func openDockerDesktop() {
        let candidates = ["/Applications/Docker.app", "/Applications/OrbStack.app", "/Applications/Rancher Desktop.app"]
        if let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) {
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: .init())
        }
    }
}
