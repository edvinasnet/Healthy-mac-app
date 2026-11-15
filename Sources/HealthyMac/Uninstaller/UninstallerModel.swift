import AppKit
import Observation

struct AlertMessage: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

@MainActor
@Observable
final class UninstallerModel {
    enum SortMode: String, CaseIterable, Identifiable {
        case name = "Name", size = "Size"
        var id: String { rawValue }
    }

    // Apps
    var apps: [InstalledApp] = []
    var isScanning = false
    var search = ""
    var sortMode: SortMode = .name
    var selectedAppID: String?

    // Leftovers for selected app
    var leftovers: [Leftover] = []
    var checked: Set<String> = []
    var isFinding = false
    var isRemoving = false

    // Orphans
    var orphans: [OrphanGroup] = []
    var orphanChecked: Set<String> = []
    var isScanningOrphans = false
    var orphansScanned = false

    var alert: AlertMessage?

    var selectedApp: InstalledApp? { apps.first { $0.id == selectedAppID } }

    var filteredApps: [InstalledApp] {
        var list = apps
        if !search.isEmpty {
            list = list.filter {
                $0.name.localizedCaseInsensitiveContains(search) || $0.bundleID.localizedCaseInsensitiveContains(search)
            }
        }
        if sortMode == .size { list.sort { ($0.size ?? 0) > ($1.size ?? 0) } }
        return list
    }

    var checkedSize: Int64 {
        leftovers.filter { checked.contains($0.id) }.reduce(0) { $0 + ($1.size ?? 0) }
    }

    var appBundleChecked: Bool {
        guard let app = selectedApp else { return false }
        return checked.contains(app.url.path)
    }

    // MARK: - Apps

    func scanApps() {
        guard !isScanning else { return }
        isScanning = true
        Task {
            let found = await Task.detached { AppScanner.scan() }.value
            apps = found
            isScanning = false
            computeAppSizes()
        }
    }

    private func computeAppSizes() {
        let snapshot = apps
        Task {
            for app in snapshot {
                let size = await Task.detached { FileSize.of(app.url) }.value
                if let i = apps.firstIndex(where: { $0.id == app.id }) { apps[i].size = size }
            }
        }
    }

    func handleDrop(_ urls: [URL]) -> Bool {
        var lastID: String?
        for url in urls where url.pathExtension.lowercased() == "app" {
            guard let app = AppScanner.load(url) else { continue }
            if !apps.contains(where: { $0.id == app.id }) {
                var copy = app
                copy.size = FileSize.of(url)
                apps.append(copy)
            }
            lastID = app.id
        }
        if let lastID { select(lastID) }
        return lastID != nil
    }

    func select(_ id: String?) {
        selectedAppID = id
        leftovers = []
        checked = []
        guard let app = selectedApp else { return }
        isFinding = true
        Task {
            let others = apps
            let found = await Task.detached { LeftoverFinder.find(for: app, otherApps: others) }.value
            guard selectedAppID == app.id else { return }
            let bundle = Leftover(
                url: app.url, kind: "Application", confidence: .exact,
                needsAdmin: !FileManager.default.isDeletableFile(atPath: app.url.path), size: app.size)
            leftovers = [bundle] + found
            checked = app.isSystem ? [] : Set(leftovers.filter { $0.confidence != .vendor }.map(\.id))
            isFinding = false
            computeLeftoverSizes(for: app.id)
        }
    }

    private func computeLeftoverSizes(for appID: String) {
        let items = leftovers
        Task {
            for item in items where item.size == nil {
                let size = await Task.detached { FileSize.of(item.url) }.value
                guard selectedAppID == appID else { return }
                if let i = leftovers.firstIndex(where: { $0.id == item.id }) { leftovers[i].size = size }
            }
        }
    }

    func removeChecked(useTrash: Bool) {
        guard let app = selectedApp, !isRemoving else { return }
        let urls = leftovers.filter { checked.contains($0.id) }.map(\.url)
        guard !urls.isEmpty else { return }
        isRemoving = true
        Task {
            if urls.contains(app.url) { await Remover.quitRunning(bundleID: app.bundleID) }
            let result = await Remover.remove(urls, useTrash: useTrash)
            isRemoving = false
            alert = AlertMessage(
                title: result.failed.isEmpty ? "Done" : "Finished with issues",
                message: result.summary)
            if Remover.exists(app.url) {
                select(app.id)
            } else {
                apps.removeAll { $0.id == app.id }
                select(nil)
            }
        }
    }

    // MARK: - Orphans

    func scanOrphans() {
        guard !isScanningOrphans else { return }
        isScanningOrphans = true
        Task {
            if apps.isEmpty { apps = await Task.detached { AppScanner.scan() }.value }
            let installed = apps
            var groups = await Task.detached { OrphanFinder.find(installed: installed) }.value
            orphans = groups
            orphanChecked = []
            isScanningOrphans = false
            orphansScanned = true
            // sizes
            for gi in groups.indices {
                for ii in groups[gi].items.indices {
                    let url = groups[gi].items[ii].url
                    groups[gi].items[ii].size = await Task.detached { FileSize.of(url) }.value
                }
                if gi < orphans.count, orphans[gi].id == groups[gi].id { orphans[gi] = groups[gi] }
            }
        }
    }

    var orphanCheckedSize: Int64 {
        orphans.flatMap(\.items).filter { orphanChecked.contains($0.id) }.reduce(0) { $0 + ($1.size ?? 0) }
    }

    func removeCheckedOrphans(useTrash: Bool) {
        let urls = orphans.flatMap(\.items).filter { orphanChecked.contains($0.id) }.map(\.url)
        guard !urls.isEmpty, !isRemoving else { return }
        isRemoving = true
        Task {
            let result = await Remover.remove(urls, useTrash: useTrash)
            isRemoving = false
            alert = AlertMessage(title: result.failed.isEmpty ? "Done" : "Finished with issues", message: result.summary)
            let gone = Set(result.removed)
            for i in orphans.indices { orphans[i].items.removeAll { gone.contains($0.url.path) } }
            orphans.removeAll { $0.items.isEmpty }
            orphanChecked.subtract(gone)
        }
    }
}
