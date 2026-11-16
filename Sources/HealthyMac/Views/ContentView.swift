import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case apps = "Applications"
    case orphans = "Leftover Files"
    case disk = "Disk Scan"
    case processes = "Processes"
    case docker = "Docker"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .apps: "square.grid.2x2"
        case .orphans: "doc.badge.ellipsis"
        case .disk: "internaldrive"
        case .processes: "cpu"
        case .docker: "shippingbox"
        }
    }
}

struct ContentView: View {
    @Bindable var uninstaller: UninstallerModel
    let processes: ProcessModel
    let docker: DockerModel
    let disk: DiskScanModel

    @State private var selection: SidebarItem? = .apps
    @State private var hasFDA = Permissions.hasFullDiskAccess
    @State private var monitor = SelfMonitor()

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Cleanup") {
                    row(.apps)
                    row(.orphans)
                    row(.disk)
                }
                Section("Activity") {
                    row(.processes)
                    row(.docker)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
            .safeAreaInset(edge: .top) {
                HStack(spacing: 8) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 30, height: 30)
                    Text("HealthyMac").font(.headline)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    if !hasFDA { fdaBanner }
                    Divider()
                    SelfUsageFooter(monitor: monitor)
                }
            }
        } detail: {
            switch selection ?? .apps {
            case .apps: AppsView(model: uninstaller)
            case .orphans: OrphansView(model: uninstaller)
            case .disk: DiskScanView(model: disk)
            case .processes: ProcessesView(model: processes)
            case .docker: DockerView(model: docker)
            }
        }
        .alert(item: $uninstaller.alert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message))
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            hasFDA = Permissions.hasFullDiskAccess
        }
    }

    private func row(_ item: SidebarItem) -> some View {
        Label(item.rawValue, systemImage: item.symbol).tag(item)
    }

    private var fdaBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Full Disk Access off", systemImage: "exclamationmark.shield")
                .font(.callout.bold())
                .foregroundStyle(.orange)
            Text("Some leftovers (containers, protected caches) can't be seen or removed without it.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Button("Open Settings…") { Permissions.openFullDiskAccessSettings() }
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        .padding(8)
    }
}

// MARK: - Shared bits

struct Badge: View {
    let text: String
    var color: Color = .secondary

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

extension Binding where Value == Bool {
    static func member<T: Hashable>(_ element: T, of set: Binding<Set<T>>) -> Binding<Bool> {
        Binding(
            get: { set.wrappedValue.contains(element) },
            set: { on in
                if on { set.wrappedValue.insert(element) } else { set.wrappedValue.remove(element) }
            })
    }
}

struct LeftoverRow: View {
    let item: Leftover
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.checkbox)
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.url.lastPathComponent).lineLimit(1)
                Text(item.displayPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .help(item.url.path)
            Spacer(minLength: 8)
            if item.needsAdmin {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.orange)
                    .help("Requires administrator password")
            }
            if item.confidence != .exact {
                Badge(text: item.confidence.label, color: item.confidence == .vendor ? .orange : .blue)
            }
            Badge(text: item.kind)
            Text(item.size.map(FileSize.format) ?? "…")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .trailing)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help("Reveal in Finder")
        }
        .padding(.vertical, 2)
    }
}
