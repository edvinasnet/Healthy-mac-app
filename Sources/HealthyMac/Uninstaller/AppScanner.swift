import Foundation

struct InstalledApp: Identifiable, Hashable {
    var id: String { url.path }
    let url: URL
    let name: String
    let bundleName: String?
    let bundleID: String
    let version: String
    let executableName: String?
    let isAppStore: Bool
    /// Lives on the sealed system volume (Safari etc.) — cannot be removed.
    let isSystem: Bool
    var size: Int64?
}

enum AppScanner {
    static var roots: [URL] {
        ["/Applications", NSHomeDirectory() + "/Applications"].map { URL(fileURLWithPath: $0) }
    }

    static func scan() -> [InstalledApp] {
        var apps: [InstalledApp] = []
        var seen = Set<String>()
        for root in roots {
            collect(in: root, depth: 0, into: &apps, seen: &seen)
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func collect(in dir: URL, depth: Int, into apps: inout [InstalledApp], seen: inout Set<String>) {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        else { return }

        for item in items {
            if item.pathExtension.lowercased() == "app" {
                if let app = load(item), seen.insert(app.url.standardizedFileURL.path).inserted {
                    apps.append(app)
                }
            } else if depth < 2,
                      let v = try? item.resourceValues(forKeys: Set(keys)),
                      v.isDirectory == true, v.isSymbolicLink != true {
                collect(in: item, depth: depth + 1, into: &apps, seen: &seen)
            }
        }
    }

    static func load(_ url: URL) -> InstalledApp? {
        guard let bundle = Bundle(url: url) else { return nil }
        let info = bundle.infoDictionary ?? [:]
        var display = FileManager.default.displayName(atPath: url.path)
        if display.lowercased().hasSuffix(".app") { display = String(display.dropLast(4)) }

        let readOnly = (try? url.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly ?? false
        let receipt = url.appendingPathComponent("Contents/_MASReceipt/receipt").path

        return InstalledApp(
            url: url,
            name: display,
            bundleName: (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String),
            bundleID: bundle.bundleIdentifier ?? "",
            version: (info["CFBundleShortVersionString"] as? String) ?? (info["CFBundleVersion"] as? String) ?? "",
            executableName: info["CFBundleExecutable"] as? String,
            isAppStore: FileManager.default.fileExists(atPath: receipt),
            isSystem: readOnly || url.path.hasPrefix("/System/")
        )
    }
}
