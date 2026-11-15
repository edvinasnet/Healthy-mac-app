import AppKit

enum Permissions {
    /// Classic probe: the TCC database is only readable with Full Disk Access.
    static var hasFullDiskAccess: Bool {
        let probe = NSHomeDirectory() + "/Library/Application Support/com.apple.TCC/TCC.db"
        if let handle = FileHandle(forReadingAtPath: probe) {
            try? handle.close()
            return true
        }
        return false
    }

    static func openFullDiskAccessSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
    }

    static func openAppManagementSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles")
    }

    private static func open(_ string: String) {
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }
}
