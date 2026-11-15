import Foundation
import Security

enum Confidence: Int, Comparable, Hashable {
    case exact = 0   // bundle id match or launchd job pointing into the app
    case likely = 1  // folder named like the app
    case vendor = 2  // same developer — may be shared with other apps

    static func < (a: Confidence, b: Confidence) -> Bool { a.rawValue < b.rawValue }

    var label: String {
        switch self {
        case .exact: "Exact"
        case .likely: "Name match"
        case .vendor: "Same vendor"
        }
    }
}

struct Leftover: Identifiable, Hashable {
    var id: String { url.path }
    let url: URL
    let kind: String
    let confidence: Confidence
    let needsAdmin: Bool
    var size: Int64?

    var displayPath: String { url.path.abbreviatingHome }
}

struct SearchRoot {
    let url: URL
    let kind: String
    let system: Bool
}

enum LeftoverFinder {
    static let searchRoots: [SearchRoot] = {
        let home = NSHomeDirectory()
        var roots: [SearchRoot] = []
        let user: [(String, String)] = [
            ("Library/Application Support", "Application Support"),
            ("Library/Caches", "Caches"),
            ("Library/Preferences", "Preferences"),
            ("Library/Preferences/ByHost", "Preferences"),
            ("Library/Containers", "Containers"),
            ("Library/Group Containers", "Group Containers"),
            ("Library/Saved Application State", "Saved State"),
            ("Library/Logs", "Logs"),
            ("Library/Logs/DiagnosticReports", "Crash Reports"),
            ("Library/HTTPStorages", "HTTP Storage"),
            ("Library/WebKit", "WebKit"),
            ("Library/Cookies", "Cookies"),
            ("Library/LaunchAgents", "Launch Agents"),
            ("Library/Application Scripts", "Scripts"),
            ("Library/Internet Plug-Ins", "Plug-Ins"),
            ("Library/Services", "Services"),
            ("Library/PreferencePanes", "Preference Panes"),
            ("Library/QuickLook", "QuickLook"),
            ("Library/Spotlight", "Spotlight"),
            ("Library/Screen Savers", "Screen Savers"),
            ("Library/Input Methods", "Input Methods"),
        ]
        for (path, kind) in user {
            roots.append(SearchRoot(url: URL(fileURLWithPath: home + "/" + path), kind: kind, system: false))
        }
        let system: [(String, String)] = [
            ("/Library/Application Support", "Application Support"),
            ("/Library/Caches", "Caches"),
            ("/Library/Preferences", "Preferences"),
            ("/Library/LaunchAgents", "Launch Agents"),
            ("/Library/LaunchDaemons", "Launch Daemons"),
            ("/Library/PrivilegedHelperTools", "Helper Tools"),
            ("/Library/Logs", "Logs"),
            ("/Library/Logs/DiagnosticReports", "Crash Reports"),
            ("/Library/Internet Plug-Ins", "Plug-Ins"),
            ("/Library/Extensions", "Kernel Extensions"),
            ("/Library/Audio/Plug-Ins/HAL", "Audio Plug-Ins"),
            ("/Library/Audio/Plug-Ins/Components", "Audio Plug-Ins"),
            ("/Library/PreferencePanes", "Preference Panes"),
            ("/Library/QuickLook", "QuickLook"),
            ("/Library/Spotlight", "Spotlight"),
            ("/Library/Screen Savers", "Screen Savers"),
            ("/Library/Input Methods", "Input Methods"),
            ("/private/var/db/receipts", "Installer Receipts"),
        ]
        for (path, kind) in system {
            roots.append(SearchRoot(url: URL(fileURLWithPath: path), kind: kind, system: true))
        }
        // Per-user temp & cache dirs under /var/folders.
        for name in [_CS_DARWIN_USER_CACHE_DIR, _CS_DARWIN_USER_TEMP_DIR] {
            if let dir = confstrString(name) {
                roots.append(SearchRoot(url: URL(fileURLWithPath: dir), kind: "Temporary", system: false))
            }
        }
        return roots
    }()

    private static func confstrString(_ name: Int32) -> String? {
        let len = confstr(name, nil, 0)
        guard len > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: len)
        guard confstr(name, &buffer, len) > 0 else { return nil }
        let s = String(cString: buffer)
        return s.hasSuffix("/") ? String(s.dropLast()) : s
    }

    // MARK: - Matching

    private struct Context {
        let bundleID: String
        let names: Set<String>
        let crashPrefixes: [String]
        let vendorPrefix: String?
        let teamID: String?
        let appPath: String
    }

    private static let genericExecutables: Set<String> = [
        "electron", "app", "main", "run", "launcher", "helper", "java", "python", "node", "stub",
        "applet", "wrapper", "start",
    ]
    private static let genericVendors: Set<String> = [
        "com.github.", "io.github.", "com.electron.", "org.chromium.", "com.apple.", "org.gnu.",
        "com.example.", "org.python.", "org.nodejs.",
    ]

    static func normalize(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    static func strip(_ name: String) -> String {
        var n = name
        let exts = [".plist", ".savedstate", ".binarycookies", ".bom", ".log", ".ips", ".crash", ".diag", ".lockfile", ".sfl2", ".sfl3"]
        for ext in exts where n.lowercased().hasSuffix(ext) {
            n = String(n.dropLast(ext.count))
        }
        return n
    }

    private static func context(for app: InstalledApp) -> Context {
        let bid = app.bundleID.lowercased()
        var names = Set<String>()
        var crash: [String] = []
        for candidate in [app.name, app.bundleName, app.executableName].compactMap({ $0 }) {
            let n = normalize(candidate)
            if n.count >= 3, !genericExecutables.contains(n) { names.insert(n) }
        }
        if let exec = app.executableName?.lowercased(), !genericExecutables.contains(exec) {
            crash.append(exec)
        }
        crash.append(app.name.lowercased())

        var vendor: String?
        let parts = bid.split(separator: ".")
        if parts.count >= 3 {
            let v = parts.prefix(2).joined(separator: ".") + "."
            if !genericVendors.contains(v) { vendor = v }
        }
        return Context(
            bundleID: bid, names: names, crashPrefixes: crash, vendorPrefix: vendor,
            teamID: teamIdentifier(for: app.url)?.lowercased(),
            appPath: app.url.standardizedFileURL.path)
    }

    private static func match(_ entry: String, root: SearchRoot, ctx: Context) -> Confidence? {
        let base = strip(entry).lowercased()
        let bid = ctx.bundleID
        if !bid.isEmpty {
            if base == bid || base.hasPrefix(bid + ".") || base.hasPrefix(bid + "-") || base.hasPrefix(bid + "_")
                || base.hasSuffix("." + bid) || base.contains("." + bid + ".") {
                return .exact
            }
        }
        if root.kind == "Crash Reports" {
            for p in ctx.crashPrefixes where base.hasPrefix(p + "-") || base.hasPrefix(p + "_") {
                return .likely
            }
            return nil
        }
        let nb = normalize(base)
        if nb.count >= 3, ctx.names.contains(nb) { return .likely }
        if root.kind == "Group Containers", let team = ctx.teamID, base.hasPrefix(team + ".") { return .vendor }
        if let v = ctx.vendorPrefix, base.hasPrefix(v) { return .vendor }
        return nil
    }

    /// Inspects a launchd plist: does it run something inside the app, or declare the app as owner?
    private static func launchdMatch(_ url: URL, ctx: Context, helpers: inout Set<String>) -> Confidence? {
        guard url.pathExtension == "plist",
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }

        let program = (plist["Program"] as? String) ?? (plist["ProgramArguments"] as? [String])?.first
        var associated: [String] = []
        if let s = plist["AssociatedBundleIdentifiers"] as? String { associated = [s] }
        if let a = plist["AssociatedBundleIdentifiers"] as? [String] { associated = a }

        let pointsIntoApp = program.map { $0.hasPrefix(ctx.appPath + "/") } ?? false
        let ownedByApp = !ctx.bundleID.isEmpty && associated.contains { $0.lowercased() == ctx.bundleID }
        guard pointsIntoApp || ownedByApp else { return nil }

        if let program, program.hasPrefix("/Library/PrivilegedHelperTools/") { helpers.insert(program) }
        return .exact
    }

    /// - Parameter otherApps: other installed apps; vendor matches are upgraded to `.likely`
    ///   when no other installed app shares the vendor prefix.
    static func find(for app: InstalledApp, otherApps: [InstalledApp] = []) -> [Leftover] {
        let ctx = context(for: app)
        let vendorShared = ctx.vendorPrefix.map { vp in
            otherApps.contains { $0.id != app.id && $0.bundleID.lowercased().hasPrefix(vp) }
        } ?? true
        let fm = FileManager.default
        var results: [String: Leftover] = [:]
        var helpers = Set<String>()

        func add(_ url: URL, kind: String, confidence: Confidence) {
            let path = url.standardizedFileURL.path
            guard path != ctx.appPath, SafetyGuard.isSafe(url) else { return }
            if let existing = results[path], existing.confidence <= confidence { return }
            results[path] = Leftover(
                url: url, kind: kind, confidence: confidence,
                needsAdmin: !fm.isDeletableFile(atPath: path))
        }

        for root in searchRoots {
            guard let entries = try? fm.contentsOfDirectory(atPath: root.url.path) else { continue }
            for entry in entries where entry != ".DS_Store" && entry != ".localized" {
                let url = root.url.appendingPathComponent(entry)
                var confidence = match(entry, root: root, ctx: ctx)
                if root.kind.hasPrefix("Launch") {
                    if let c = launchdMatch(url, ctx: ctx, helpers: &helpers) {
                        confidence = min(confidence ?? c, c)
                    }
                }
                if var confidence {
                    if confidence == .vendor, !vendorShared, let vp = ctx.vendorPrefix, entry.lowercased().hasPrefix(vp) {
                        confidence = .likely
                    }
                    add(url, kind: root.kind, confidence: confidence)
                }
            }
        }
        for helper in helpers where fm.fileExists(atPath: helper) {
            add(URL(fileURLWithPath: helper), kind: "Helper Tools", confidence: .exact)
        }

        return results.values.sorted {
            if $0.confidence != $1.confidence { return $0.confidence < $1.confidence }
            return $0.url.path.localizedCaseInsensitiveCompare($1.url.path) == .orderedAscending
        }
    }

    static func teamIdentifier(for url: URL) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any]
        else { return nil }
        return dict[kSecCodeInfoTeamIdentifier as String] as? String
    }
}
