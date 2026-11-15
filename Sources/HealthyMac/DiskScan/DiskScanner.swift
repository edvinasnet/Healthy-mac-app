import Darwin
import Foundation

/// A folder (or large file) in the size tree. Small children are merged into
/// `hiddenCount` / `hiddenSize` during the scan to keep memory bounded.
final class DirNode: Identifiable {
    let name: String
    weak var parent: DirNode?
    let isFile: Bool
    var size: Int64 = 0
    var modified: Date?
    var children: [DirNode] = []
    var hiddenCount = 0
    var hiddenSize: Int64 = 0
    var junk: JunkRule?

    init(name: String, parent: DirNode?, isFile: Bool = false) {
        self.name = name
        self.parent = parent
        self.isFile = isFile
    }

    var path: String {
        guard let parent else { return name }
        let base = parent.path
        return base == "/" ? "/" + name : base + "/" + name
    }
}

struct JunkItem: Identifiable, Hashable {
    let node: DirNode
    let path: String
    var id: String { path }
    var kind: String { node.junk?.kind ?? "" }
    var note: String { node.junk?.note ?? "" }

    static func == (a: JunkItem, b: JunkItem) -> Bool { a.path == b.path }
    func hash(into h: inout Hasher) { h.combine(path) }
}

struct ScanProgress {
    var files = 0
    var bytes: Int64 = 0
    var path = ""
}

struct ScanResult {
    let root: DirNode
    let junk: [JunkItem]
    let largeFiles: [DirNode]
    let files: Int
    let inaccessible: Int
    let duration: TimeInterval
    let cancelled: Bool
}

final class ScanCancel: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    var isCancelled: Bool { lock.withLock { flag } }
    func cancel() { lock.withLock { flag = true } }
}

enum DiskScanner {
    static let keepDirMin: Int64 = 1 << 20          // keep folders ≥ 1 MB in the tree
    static let keepFileMin: Int64 = 25 << 20        // keep files ≥ 25 MB in the tree
    static let largeFileMin: Int64 = 100 << 20      // "Large Files" list
    static let junkMin: Int64 = 1 << 20             // report generated folders ≥ 1 MB

    /// Walks `root` on a single volume (`FTS_XDEV`), never following symlinks.
    /// - Parameters:
    ///   - root: real path to walk (e.g. /System/Volumes/Data).
    ///   - alias: how `root` should appear in results (e.g. "" so paths become /Users/…).
    static func scan(root: String, alias: String, cancel: ScanCancel,
                     progress: @escaping (ScanProgress) -> Void) -> ScanResult {
        let start = Date()
        var stack: [DirNode] = []
        var rootNode: DirNode?
        var junk: [JunkItem] = []
        var large: [DirNode] = []
        var files = 0
        var inaccessible = 0
        var bytes: Int64 = 0
        var collapseLevel: Int?          // inside a generated folder: sum sizes, no nodes
        var seenInodes = Set<UInt64>()   // hard links counted once
        var entries = 0
        var lastReport = Date()

        func display(_ raw: String) -> String {
            let rest = raw.dropFirst(root.count)
            let p = alias + rest
            return p.isEmpty ? "/" : p
        }

        func close(_ node: DirNode) {
            var kept: [DirNode] = []
            for child in node.children {
                let keep = child.isFile || child.size >= keepDirMin || (child.junk != nil && child.size >= junkMin)
                if keep {
                    kept.append(child)
                } else {
                    node.hiddenCount += 1
                    node.hiddenSize += child.size
                }
            }
            node.children = kept.sorted { $0.size > $1.size }
            if let parent = stack.last {
                parent.size += node.size
                parent.children.append(node)
            }
            if node.junk != nil, node.size >= junkMin {
                junk.append(JunkItem(node: node, path: node.path))
            }
        }

        var argv: [UnsafeMutablePointer<CChar>?] = [strdup(root), nil]
        defer { free(argv[0]) }
        guard let fts = fts_open(&argv, FTS_PHYSICAL | FTS_XDEV | FTS_NOCHDIR, nil) else {
            let empty = DirNode(name: alias.isEmpty ? "/" : alias, parent: nil)
            return ScanResult(root: empty, junk: [], largeFiles: [], files: 0, inaccessible: 1, duration: 0, cancelled: false)
        }
        defer { fts_close(fts) }

        var cancelled = false
        while let ent = fts_read(fts) {
            entries += 1
            if entries % 2000 == 0 {
                if cancel.isCancelled { cancelled = true; break }
                if Date().timeIntervalSince(lastReport) > 0.15 {
                    lastReport = Date()
                    progress(ScanProgress(files: files, bytes: bytes, path: stack.last?.path ?? ""))
                }
            }

            let info = Int32(ent.pointee.fts_info)
            let level = Int(ent.pointee.fts_level)

            switch info {
            case FTS_D:
                if let cl = collapseLevel, level > cl { continue }
                let raw = String(cString: ent.pointee.fts_path)
                let path = display(raw)
                let name = stack.isEmpty ? (alias.isEmpty ? "/" : alias) : (raw as NSString).lastPathComponent
                let node = DirNode(name: name, parent: stack.last)
                if let st = ent.pointee.fts_statp {
                    node.modified = Date(timeIntervalSince1970: TimeInterval(st.pointee.st_mtimespec.tv_sec))
                }
                if rootNode == nil { rootNode = node }
                if !stack.isEmpty, let rule = JunkRules.match(name: name, path: path) {
                    node.junk = rule
                    collapseLevel = level
                }
                stack.append(node)

            case FTS_DP, FTS_DNR, FTS_ERR:
                if info != FTS_DP { inaccessible += 1 }
                if let cl = collapseLevel, level > cl { continue }
                // FTS_DNR / FTS_ERR replace FTS_DP for a directory that could not be read.
                guard level == stack.count - 1, let node = stack.popLast() else { continue }
                if collapseLevel == level { collapseLevel = nil }
                close(node)

            case FTS_F, FTS_SL, FTS_SLNONE, FTS_DEFAULT:
                guard let st = ent.pointee.fts_statp else { continue }
                if info == FTS_F, st.pointee.st_nlink > 1,
                   !seenInodes.insert(UInt64(st.pointee.st_ino)).inserted {
                    continue
                }
                let size = Int64(st.pointee.st_blocks) * 512
                files += 1
                bytes += size
                guard let top = stack.last else { continue }
                top.size += size
                if collapseLevel != nil { continue }
                if size >= keepFileMin {
                    let raw = String(cString: ent.pointee.fts_path)
                    let file = DirNode(name: (raw as NSString).lastPathComponent, parent: top, isFile: true)
                    file.size = size
                    file.modified = Date(timeIntervalSince1970: TimeInterval(st.pointee.st_mtimespec.tv_sec))
                    top.children.append(file)
                    if size >= largeFileMin { large.append(file) }
                } else {
                    top.hiddenCount += 1
                    top.hiddenSize += size
                }

            case FTS_NS:
                inaccessible += 1

            default:
                break
            }
        }

        // Cancelled mid-walk: close whatever is still open so sizes add up.
        while let node = stack.popLast() { close(node) }

        let root = rootNode ?? DirNode(name: alias.isEmpty ? "/" : alias, parent: nil)
        return ScanResult(
            root: root,
            junk: junk.sorted { $0.node.size > $1.node.size },
            largeFiles: large.sorted { $0.size > $1.size },
            files: files, inaccessible: inaccessible,
            duration: Date().timeIntervalSince(start), cancelled: cancelled)
    }

    static func volumeInfo(for path: String) -> (total: Int64, free: Int64)? {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let v = try? URL(fileURLWithPath: path).resourceValues(forKeys: keys),
              let total = v.volumeTotalCapacity, let free = v.volumeAvailableCapacityForImportantUsage
        else { return nil }
        return (Int64(total), free)
    }
}
