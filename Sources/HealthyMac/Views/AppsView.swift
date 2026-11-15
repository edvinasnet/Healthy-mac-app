import SwiftUI

struct AppsView: View {
    @Bindable var model: UninstallerModel
    @AppStorage("useTrash") private var useTrash = true
    @State private var confirming = false
    @State private var dropTargeted = false

    var body: some View {
        // Plain HStack: HSplitView ignores the toolbar safe area on macOS 26 and
        // slides content under the title bar.
        HStack(spacing: 0) {
            appList
                .frame(width: 300)
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Applications")
        .task { if model.apps.isEmpty { model.scanApps() } }
    }

    // MARK: List

    private var appList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                TextField("Search apps", text: $model.search)
                    .textFieldStyle(.roundedBorder)
                Picker("Sort", selection: $model.sortMode) {
                    ForEach(UninstallerModel.SortMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                Button { model.scanApps() } label: { Image(systemName: "arrow.clockwise") }
                    .help("Rescan applications")
            }
            .padding(8)

            List(model.filteredApps, selection: Binding(get: { model.selectedAppID }, set: { model.select($0) })) { app in
                AppRow(app: app)
            }
            .overlay {
                if model.isScanning { ProgressView("Scanning…") }
            }

            Divider()
            Text("\(model.apps.count) apps · drop any .app here")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(6)
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor, lineWidth: 3).padding(2)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.handleDrop(urls)
        } isTargeted: { dropTargeted = $0 }
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if let app = model.selectedApp {
            VStack(spacing: 0) {
                header(app)
                Divider()
                if model.isFinding {
                    ProgressView("Looking for related files…").frame(maxHeight: .infinity)
                } else {
                    List {
                        ForEach(model.leftovers) { item in
                            LeftoverRow(item: item, isOn: .member(item.id, of: $model.checked))
                        }
                    }
                }
                Divider()
                footer(app)
            }
        } else {
            ContentUnavailableView(
                "Select an app",
                systemImage: "app.dashed",
                description: Text("HealthyMac finds the app bundle plus its caches, preferences, containers, launch agents, helpers and receipts."))
        }
    }

    private func header(_ app: InstalledApp) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                .resizable()
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(app.name).font(.title2.bold())
                    if !app.version.isEmpty { Text(app.version).foregroundStyle(.secondary) }
                }
                Text(app.bundleID.isEmpty ? "no bundle identifier" : app.bundleID)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                HStack(spacing: 6) {
                    if app.isAppStore { Badge(text: "App Store", color: .blue) }
                    if app.isSystem { Badge(text: "System app — protected", color: .red) }
                    Text(app.url.path.abbreviatingHome).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(14)
    }

    private func footer(_ app: InstalledApp) -> some View {
        HStack {
            Button("All") { model.checked = Set(model.leftovers.map(\.id)) }
            Button("None") { model.checked = [] }
            Text("\(model.checked.count) of \(model.leftovers.count) selected · \(FileSize.format(model.checkedSize))")
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Spacer()
            Toggle("Move to Trash", isOn: $useTrash)
                .help("Off = delete permanently. Admin-owned files are always deleted permanently.")
            Button(role: .destructive) {
                confirming = true
            } label: {
                if model.isRemoving {
                    ProgressView().controlSize(.small)
                } else {
                    Text(model.appBundleChecked ? "Uninstall" : "Remove Selected")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(model.checked.isEmpty || model.isRemoving || app.isSystem)
            .confirmationDialog(
                model.appBundleChecked ? "Uninstall \(app.name)?" : "Remove \(model.checked.count) selected item(s)?",
                isPresented: $confirming
            ) {
                Button(useTrash ? "Move to Trash" : "Delete Permanently", role: .destructive) {
                    model.removeChecked(useTrash: useTrash)
                }
            } message: {
                Text("\(model.checked.count) item(s), \(FileSize.format(model.checkedSize)). The app will be quit first if running.")
            }
        }
        .padding(10)
    }
}

struct AppRow: View {
    let app: InstalledApp

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                .resizable()
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name).lineLimit(1)
                Text(app.version.isEmpty ? app.bundleID : app.version)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if let size = app.size {
                Text(FileSize.format(size))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .opacity(app.isSystem ? 0.55 : 1)
    }
}
