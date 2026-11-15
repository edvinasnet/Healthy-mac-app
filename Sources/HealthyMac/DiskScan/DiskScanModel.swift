import AppKit
import Observation

@MainActor
@Observable
final class DiskScanModel {
    enum Scope: Hashable {
        case home, disk, folder(URL)

        var title: String {
            switch self {
            case .home: "Home"
            case .disk: "Entire Disk"
            case .folder(let url): url.lastPathComponent
            }
        }
    }

    enum Tab: String, CaseIterable, Identifiable {
        case generated = "Generated & Caches"
        case large = "Large Files"
        case explorer = "Explorer"
        var id: String { rawValue }
    }

    enum JunkSort: String, CaseIterable, Identifiable {
        case size = "Size", age = "Oldest first"
        var id: String { rawValue }
    }

    var scope: Scope = .home
    var tab: Tab = .generated
    var isScanning = false
    var progress = ScanProgress()
    var result: ScanResult?

    var junk: [JunkItem] = []
    var junkSelected = Set<String>()
    var kindFilter: String?
    var junkSort: JunkSort = .size

    var largeFiles: [DirNode] = []
    var largeSelected = Set<String>()

    var current: DirNode?
    var isRemoving = false
    var alert: AlertMessage?
    /// DirNode is a plain class; bump this after mutating the tree so views re-render.
    var revision = 0

    private var cancelToken: ScanCancel?

    // MARK: - Derived

    var kinds: [(kind: String, count: Int, size: Int64)] {
        var map: [String: (Int, Int64)] = [:]
        for item in junk {
            map[item.kind, default: (0, 0)].0 += 1
            map[item.kind]!.1 += item.node.size
        }
        return map.map { ($0.key, $0.value.0, $0.value.1) }.sorted { $0.size > $1.size }
    }

    var visibleJunk: [JunkItem] {
        var list = junk
        if let kindFilter { list = list.filter { $0.kind == kindFilter } }
        switch junkSort {
        case .size: list.sort { $0.node.size > $1.node.size }
        case .age: list.sort { ($0.node.modified ?? .distantPast) < ($1.node.modified ?? .distantPast) }
        }
        return list
    }

    var junkTotal: Int64 { junk.reduce(0) { $0 + $1.node.size } }
    var junkSelectedSize: Int64 { junk.filter { junkSelected.contains($0.id) }.reduce(0) { $0 + $1.node.size } }
    var largeSelectedSize: Int64 { largeFiles.filter { largeSelected.contains($0.path) }.reduce(0) { $0 + $1.size } }

    var volume: (total: Int64, free: Int64)? { DiskScanner.volumeInfo(for: NSHomeDirectory()) }

    // MARK: - Scanning

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Scan"
        if panel.runModal() == .OK, let url = panel.url {
            scope = .folder(url)
            scan()
        }
    }

    func scan() {
        guard !isScanning else { return }
        let (root, alias): (String, String) = switch scope {
        case .home: (NSHomeDirectory(), NSHomeDirectory())
        case .disk: ("/System/Volumes/Data", "")   // data volume; paths reported as /Users/…
        case .folder(let url): (url.path, url.path)
        }
        let token = ScanCancel()
        cancelToken = token
        isScanning = true
        progress = ScanProgress()
        result = nil
        junk = []
        largeFiles = []
        junkSelected = []
        largeSelected = []
        kindFilter = nil
        current = nil

        Task {
            let res = await Task.detached {
                DiskScanner.scan(root: root, alias: alias, cancel: token) { p in
                    Task { @MainActor [weak self] in
                        if self?.isScanning == true { self?.progress = p }
                    }
                }
            }.value
            result = res
            junk = res.junk
            largeFiles = res.largeFiles
            current = res.root
            isScanning = false
            revision += 1
        }
    }

    func cancelScan() { cancelToken?.cancel() }

    // MARK: - Selection helpers

    func selectJunk(olderThanDays days: Int) {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
        junkSelected = Set(visibleJunk.filter { ($0.node.modified ?? .distantPast) < cutoff }.map(\.id))
    }

    // MARK: - Removal

    func removeSelectedJunk(useTrash: Bool) {
        remove(junk.filter { junkSelected.contains($0.id) }.map(\.node), useTrash: useTrash)
    }

    func removeSelectedLarge(useTrash: Bool) {
        remove(largeFiles.filter { largeSelected.contains($0.path) }, useTrash: useTrash)
    }

    func remove(_ nodes: [DirNode], useTrash: Bool) {
        guard !nodes.isEmpty, !isRemoving else { return }
        isRemoving = true
        let byPath = Dictionary(nodes.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
        Task {
            let res = await Remover.remove(byPath.keys.map { URL(fileURLWithPath: $0) }, useTrash: useTrash)
            var freed: Int64 = 0
            for path in res.removed {
                guard let node = byPath[path] else { continue }
                freed += node.size
                detach(node)
                if current.map({ isDescendant($0, of: node) }) == true { current = node.parent }
            }
            let gone = res.removed
            func isGone(_ p: String) -> Bool { gone.contains { p == $0 || p.hasPrefix($0 + "/") } }
            junk.removeAll { isGone($0.path) }
            largeFiles.removeAll { isGone($0.path) }
            junkSelected = junkSelected.filter { !isGone($0) }
            largeSelected = largeSelected.filter { !isGone($0) }
            isRemoving = false
            revision += 1

            var message = res.summary + "\nFreed \(FileSize.format(freed))."
            if useTrash { message += "\nSpace is reclaimed when you empty the Trash." }
            alert = AlertMessage(title: res.failed.isEmpty ? "Done" : "Finished with issues", message: message)
        }
    }

    private func detach(_ node: DirNode) {
        let size = node.size
        node.parent?.children.removeAll { $0 === node }
        var ancestor = node.parent
        while let a = ancestor {
            a.size -= size
            ancestor = a.parent
        }
    }

    private func isDescendant(_ node: DirNode, of other: DirNode) -> Bool {
        var n: DirNode? = node
        while let x = n {
            if x === other { return true }
            n = x.parent
        }
        return false
    }
}
