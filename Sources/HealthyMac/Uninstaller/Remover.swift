import AppKit

enum Remover {
    struct Result {
        var removed: [String] = []
        var failed: [(path: String, reason: String)] = []

        var summary: String {
            var lines = ["Removed \(removed.count) item(s)."]
            if !failed.isEmpty {
                lines.append("Failed \(failed.count):")
                lines += failed.prefix(12).map { "• \($0.path.abbreviatingHome) — \($0.reason)" }
                if failed.count > 12 { lines.append("…and \(failed.count - 12) more") }
                if failed.contains(where: { $0.reason.localizedCaseInsensitiveContains("not permitted") }) {
                    lines.append("\nTip: grant HealthyMac Full Disk Access and App Management in System Settings → Privacy & Security.")
                }
            }
            return lines.joined(separator: "\n")
        }
    }

    /// Quits a running app politely, then forcefully.
    @MainActor
    static func quitRunning(bundleID: String) async {
        guard !bundleID.isEmpty else { return }
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        guard !running.isEmpty else { return }
        running.forEach { $0.terminate() }
        for _ in 0..<20 {
            if running.allSatisfy(\.isTerminated) { return }
            try? await Task.sleep(for: .milliseconds(150))
        }
        running.forEach { $0.forceTerminate() }
        try? await Task.sleep(for: .milliseconds(300))
    }

    @MainActor
    static func remove(_ urls: [URL], useTrash: Bool) async -> Result {
        var result = Result()
        var candidates: [URL] = []
        for url in urls {
            if SafetyGuard.isSafe(url) { candidates.append(url) } else { result.failed.append((url.path, "Blocked by safety guard")) }
        }

        let pass = await Task.detached { userPass(candidates, useTrash: useTrash) }.value
        result.removed += pass.removed
        result.failed += pass.failed

        if !pass.needAdmin.isEmpty {
            var adminError: String?
            do {
                try Shell.runAsAdmin(adminCommand(for: pass.needAdmin))
            } catch {
                adminError = error.localizedDescription
            }
            for url in pass.needAdmin {
                if exists(url) {
                    result.failed.append((url.path, adminError ?? "Operation not permitted"))
                } else {
                    result.removed.append(url.path)
                }
            }
        }
        return result
    }

    private static func userPass(_ urls: [URL], useTrash: Bool) -> (removed: [String], needAdmin: [URL], failed: [(String, String)]) {
        let fm = FileManager.default
        let uid = getuid()
        var removed: [String] = []
        var needAdmin: [URL] = []
        var failed: [(String, String)] = []

        for url in urls {
            guard exists(url) else { removed.append(url.path); continue }
            if isLaunchdPlist(url), !url.path.hasPrefix("/Library/LaunchDaemons/") {
                _ = Shell.run("/bin/launchctl", ["bootout", "gui/\(uid)", url.path], timeout: 5)
            }
            guard fm.isDeletableFile(atPath: url.path) else { needAdmin.append(url); continue }
            do {
                if useTrash {
                    try fm.trashItem(at: url, resultingItemURL: nil)
                } else {
                    try fm.removeItem(at: url)
                }
                removed.append(url.path)
            } catch {
                if !exists(url) {
                    removed.append(url.path)
                } else if (error as NSError).code == NSFileWriteVolumeReadOnlyError {
                    failed.append((url.path, "Read-only (system) volume"))
                } else {
                    // Permission errors and partially deleted trees with root-owned contents.
                    needAdmin.append(url)
                }
            }
        }
        return (removed, needAdmin, failed)
    }

    private static func adminCommand(for urls: [URL]) -> String {
        var parts: [String] = []
        for url in urls where url.path.hasPrefix("/Library/LaunchDaemons/") {
            parts.append("/bin/launchctl bootout system \(Shell.quote(url.path)) 2>/dev/null")
        }
        parts.append("/bin/rm -rf " + urls.map { Shell.quote($0.path) }.joined(separator: " "))
        return parts.joined(separator: "; ")
    }

    private static func isLaunchdPlist(_ url: URL) -> Bool {
        url.pathExtension == "plist" && url.deletingLastPathComponent().lastPathComponent.hasPrefix("Launch")
    }

    /// lstat-based existence (true for broken symlinks too).
    static func exists(_ url: URL) -> Bool {
        var st = stat()
        return lstat(url.path, &st) == 0
    }
}
