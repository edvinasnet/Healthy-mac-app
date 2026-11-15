import Foundation

/// Last line of defence: refuses to delete system locations or well-known parent folders.
enum SafetyGuard {
    static let home = NSHomeDirectory()

    static let protectedPaths: Set<String> = {
        var set: Set<String> = [
            "/", "/System", "/Library", "/Applications", "/Applications/Utilities", "/Users",
            "/Users/Shared", "/usr", "/usr/local", "/bin", "/sbin", "/etc", "/var", "/tmp", "/opt",
            "/private", "/private/var", "/private/etc", "/private/tmp", "/private/var/db",
            "/private/var/db/receipts", "/private/var/folders", "/var/folders", "/Volumes", "/cores",
            home,
        ]
        for sub in [
            "Library", "Documents", "Desktop", "Downloads", "Applications", "Movies", "Music",
            "Pictures", "Public", ".Trash", "Library/Mobile Documents", "Library/CloudStorage",
        ] {
            set.insert(home + "/" + sub)
        }
        for root in LeftoverFinder.searchRoots {
            set.insert(root.url.standardizedFileURL.path)
        }
        return set
    }()

    static func isSafe(_ url: URL) -> Bool {
        let std = url.standardizedFileURL
        let path = std.path
        guard path.hasPrefix("/"), std.pathComponents.count >= 3 else { return false }
        if protectedPaths.contains(path) { return false }
        if home.hasPrefix(path + "/") { return false }
        let forbiddenPrefixes = ["/System/", "/bin/", "/sbin/", "/etc/", "/private/etc/"]
        if forbiddenPrefixes.contains(where: { path.hasPrefix($0) }) { return false }
        if path.hasPrefix("/usr/") && !path.hasPrefix("/usr/local/") { return false }
        // Never delete ourselves.
        if path == Bundle.main.bundleURL.standardizedFileURL.path { return false }
        return true
    }
}
