import AppKit

/// Data left behind by apps that are no longer installed.
struct OrphanGroup: Identifiable, Hashable {
    let id: String
    let reason: String
    var items: [Leftover]
    var size: Int64 { items.reduce(0) { $0 + ($1.size ?? 0) } }
}

enum OrphanFinder {
    private static let kinds: Set<String> = [
        "Application Support", "Caches", "Preferences", "Containers", "Group Containers",
        "Saved State", "HTTP Storage", "WebKit", "Cookies", "Logs", "Scripts",
    ]
    private static let ignoredPrefixes = [
        "com.apple.", "apple.", "group.com.apple.", "systemgroup.", "com.crashlytics",
        "org.swift.", "com.google.keystone", "com.microsoft.autoupdate",
    ]
    private static let reverseDNS = try! NSRegularExpression(
        pattern: #"^[a-z0-9][a-z0-9-]*(\.[a-z0-9][a-z0-9_-]*){2,}$"#, options: [.caseInsensitive])
    private static let teamPrefix = try! NSRegularExpression(pattern: #"^[a-z0-9]{10}\."#, options: [.caseInsensitive])
    private static let uuidSuffix = try! NSRegularExpression(
        pattern: #"\.[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"#, options: [.caseInsensitive])

    static func find(installed: [InstalledApp]) -> [OrphanGroup] {
        let installedIDs = Set(installed.map { $0.bundleID.lowercased() }.filter { !$0.isEmpty })
        let fm = FileManager.default
        var groups: [String: OrphanGroup] = [:]
        var lsCache: [String: Bool] = [:]

        func isInstalled(_ ident: String) -> Bool {
            if installedIDs.contains(ident) { return true }
            for iid in installedIDs where ident.hasPrefix(iid + ".") || iid.hasPrefix(ident + ".") {
                return true
            }
            var comps = ident.split(separator: ".").map(String.init)
            while comps.count >= 3 {
                let candidate = comps.joined(separator: ".")
                if let cached = lsCache[candidate] {
                    if cached { return true }
                } else {
                    let found = NSWorkspace.shared.urlForApplication(withBundleIdentifier: candidate) != nil
                    lsCache[candidate] = found
                    if found { return true }
                }
                comps.removeLast()
            }
            return false
        }

        func add(_ url: URL, ident: String, kind: String, reason: String, confidence: Confidence) {
            guard SafetyGuard.isSafe(url) else { return }
            let item = Leftover(url: url, kind: kind, confidence: confidence,
                                needsAdmin: !fm.isDeletableFile(atPath: url.path))
            groups[ident, default: OrphanGroup(id: ident, reason: reason, items: [])].items.append(item)
        }

        // 1. Bundle-id-named folders whose app is gone.
        for root in LeftoverFinder.searchRoots where !root.system && kinds.contains(root.kind) {
            guard let entries = try? fm.contentsOfDirectory(atPath: root.url.path) else { continue }
            for entry in entries {
                var ident = LeftoverFinder.strip(entry).lowercased()
                ident = replace(uuidSuffix, in: ident)
                if root.kind == "Group Containers" || root.kind == "Scripts" {
                    ident = replace(teamPrefix, in: ident)
                    for prefix in ["group.", "groups."] where ident.hasPrefix(prefix) { ident.removeFirst(prefix.count) }
                }
                guard matches(reverseDNS, ident),
                      !ignoredPrefixes.contains(where: { ident.hasPrefix($0) }),
                      !isInstalled(ident)
                else { continue }
                add(root.url.appendingPathComponent(entry), ident: ident, kind: root.kind,
                    reason: "No installed app with this bundle identifier", confidence: .likely)
            }
        }

        // 2. Launch agents/daemons whose program no longer exists.
        for root in LeftoverFinder.searchRoots where root.kind.hasPrefix("Launch") {
            guard let entries = try? fm.contentsOfDirectory(atPath: root.url.path) else { continue }
            for entry in entries where entry.hasSuffix(".plist") {
                let url = root.url.appendingPathComponent(entry)
                guard let data = try? Data(contentsOf: url),
                      let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                      let program = (plist["Program"] as? String) ?? (plist["ProgramArguments"] as? [String])?.first,
                      program.hasPrefix("/"), !fm.fileExists(atPath: program)
                else { continue }
                let ident = LeftoverFinder.strip(entry).lowercased()
                guard !ignoredPrefixes.contains(where: { ident.hasPrefix($0) }) else { continue }
                add(url, ident: ident, kind: root.kind,
                    reason: "Launch job points to missing program \(program.abbreviatingHome)", confidence: .exact)
            }
        }

        return groups.values.sorted { $0.id < $1.id }
    }

    private static func matches(_ regex: NSRegularExpression, _ s: String) -> Bool {
        regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    private static func replace(_ regex: NSRegularExpression, in s: String) -> String {
        regex.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
    }
}
