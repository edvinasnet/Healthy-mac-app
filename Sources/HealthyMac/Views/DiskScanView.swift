import SwiftUI

struct DiskScanView: View {
    @Bindable var model: DiskScanModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if model.isScanning {
                scanningView
            } else if let result = model.result {
                summary(result)
                Divider()
                switch model.tab {
                case .generated: GeneratedListView(model: model)
                case .large: LargeFilesView(model: model)
                case .explorer: ExplorerView(model: model)
                }
            } else {
                ContentUnavailableView {
                    Label("Find what fills your disk", systemImage: "internaldrive")
                } description: {
                    Text("Scans every folder once and finds regenerable build output and caches (node_modules, .next, target, Pods, .venv, DerivedData, package caches…), the largest files, and lets you browse folders by size.")
                } actions: {
                    Button("Scan \(model.scope.title)") { model.scan() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("Disk Scan")
        .alert(item: $model.alert) { Alert(title: Text($0.title), message: Text($0.message)) }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            Picker("Scope", selection: Binding(
                get: { model.scope },
                set: { model.scope = $0 }
            )) {
                Text("Home").tag(DiskScanModel.Scope.home)
                Text("Entire Disk").tag(DiskScanModel.Scope.disk)
                if case .folder = model.scope { Text(model.scope.title).tag(model.scope) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .disabled(model.isScanning)

            Button("Folder…") { model.chooseFolder() }
                .disabled(model.isScanning)

            if model.isScanning {
                Button("Cancel") { model.cancelScan() }
            } else {
                Button(model.result == nil ? "Scan" : "Rescan") { model.scan() }
                    .buttonStyle(.borderedProminent)
            }

            Spacer()

            if let v = model.volume {
                VStack(alignment: .trailing, spacing: 3) {
                    Text("\(FileSize.format(v.free)) free of \(FileSize.format(v.total))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    ProgressView(value: Double(v.total - v.free), total: Double(max(v.total, 1)))
                        .frame(width: 160)
                        .tint(Double(v.free) / Double(max(v.total, 1)) < 0.1 ? .red : .accentColor)
                }
            }
        }
        .padding(10)
    }

    private var scanningView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("\(model.progress.files.formatted()) files · \(FileSize.format(model.progress.bytes))")
                .font(.title3.monospacedDigit())
            Text(model.progress.path.abbreviatingHome)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 600)
            if model.scope == .disk {
                Text("A full disk scan can take a few minutes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func summary(_ r: ScanResult) -> some View {
        HStack(spacing: 12) {
            Picker("View", selection: $model.tab) {
                ForEach(DiskScanModel.Tab.allCases) { tab in
                    switch tab {
                    case .generated: Text("\(tab.rawValue) · \(FileSize.format(model.junkTotal))").tag(tab)
                    case .large: Text("\(tab.rawValue) · \(model.largeFiles.count)").tag(tab)
                    case .explorer: Text(tab.rawValue).tag(tab)
                    }
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(r.files.formatted()) files · \(FileSize.format(r.root.size)) · \(String(format: "%.0f", r.duration)) s\(r.cancelled ? " · cancelled" : "")")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                if r.inaccessible > 0 {
                    Text("\(r.inaccessible.formatted()) items unreadable\(Permissions.hasFullDiskAccess ? "" : " — grant Full Disk Access")")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}

// MARK: - Shared helpers

private let relativeFormatter: RelativeDateTimeFormatter = {
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .short
    return f
}()

func ageText(_ date: Date?) -> String {
    guard let date else { return "" }
    return relativeFormatter.localizedString(for: date, relativeTo: Date())
}

func isStale(_ date: Date?, days: Int = 30) -> Bool {
    guard let date else { return false }
    return date < Date().addingTimeInterval(-Double(days) * 86400)
}

private struct RemoveBar: View {
    let selectedCount: Int
    let selectedSize: Int64
    let isRemoving: Bool
    let onRemove: (Bool) -> Void
    @AppStorage("useTrash") private var useTrash = true
    @State private var confirming = false

    var body: some View {
        HStack {
            Text("\(selectedCount) selected · \(FileSize.format(selectedSize))")
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Spacer()
            Toggle("Move to Trash", isOn: $useTrash)
                .help("Trash frees space only after you empty it")
            Button(role: .destructive) { confirming = true } label: {
                if isRemoving { ProgressView().controlSize(.small) } else { Text("Delete Selected") }
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(selectedCount == 0 || isRemoving)
            .confirmationDialog("Delete \(selectedCount) item(s), \(FileSize.format(selectedSize))?", isPresented: $confirming) {
                Button(useTrash ? "Move to Trash" : "Delete Permanently", role: .destructive) { onRemove(useTrash) }
            }
        }
    }
}

// MARK: - Generated & caches

struct GeneratedListView: View {
    @Bindable var model: DiskScanModel

    var body: some View {
        let _ = model.revision
        VStack(spacing: 0) {
            HStack {
                Picker("Kind", selection: $model.kindFilter) {
                    Text("All kinds (\(model.junk.count))").tag(String?.none)
                    Divider()
                    ForEach(model.kinds, id: \.kind) { k in
                        Text("\(k.kind) — \(k.count) · \(FileSize.format(k.size))").tag(String?.some(k.kind))
                    }
                }
                .fixedSize()
                Picker("Sort", selection: $model.junkSort) {
                    ForEach(DiskScanModel.JunkSort.allCases) { Text($0.rawValue).tag($0) }
                }
                .fixedSize()
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            if model.visibleJunk.isEmpty {
                ContentUnavailableView("Nothing found", systemImage: "checkmark.seal",
                                       description: Text("No regenerable folders over 1 MB in this scope."))
            } else {
                List(model.visibleJunk) { item in
                    JunkRow(item: item, isOn: .member(item.id, of: $model.junkSelected))
                }
            }
            Divider()
            HStack {
                Button("Select unused > 30 days") { model.selectJunk(olderThanDays: 30) }
                    .help("Folders not modified for 30 days — likely old projects")
                Button("All") { model.junkSelected = Set(model.visibleJunk.map(\.id)) }
                Button("None") { model.junkSelected = [] }
                RemoveBar(selectedCount: model.junkSelected.count, selectedSize: model.junkSelectedSize,
                          isRemoving: model.isRemoving) { model.removeSelectedJunk(useTrash: $0) }
            }
            .padding(10)
        }
    }
}

private struct JunkRow: View {
    let item: JunkItem
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.checkbox)
            Image(systemName: "folder.fill").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(item.node.name).lineLimit(1)
                    Badge(text: item.kind, color: .blue)
                }
                Text((item.path as NSString).deletingLastPathComponent.abbreviatingHome)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            .help("\(item.path)\n\(item.note)")
            Spacer(minLength: 8)
            Text(ageText(item.node.modified))
                .font(.caption)
                .foregroundStyle(isStale(item.node.modified) ? .orange : .secondary)
                .frame(width: 90, alignment: .trailing)
                .help("Last modified")
            Text(FileSize.format(item.node.size))
                .font(.callout.monospacedDigit())
                .frame(width: 80, alignment: .trailing)
            Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)]) } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help("Reveal in Finder")
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Large files

struct LargeFilesView: View {
    @Bindable var model: DiskScanModel

    var body: some View {
        let _ = model.revision
        VStack(spacing: 0) {
            if model.largeFiles.isEmpty {
                ContentUnavailableView("No large files", systemImage: "doc",
                                       description: Text("No files of 100 MB or more in this scope."))
            } else {
                List(model.largeFiles) { file in
                    LargeFileRow(file: file, isOn: .member(file.path, of: $model.largeSelected))
                }
            }
            Divider()
            HStack {
                Button("None") { model.largeSelected = [] }
                RemoveBar(selectedCount: model.largeSelected.count, selectedSize: model.largeSelectedSize,
                          isRemoving: model.isRemoving) { model.removeSelectedLarge(useTrash: $0) }
            }
            .padding(10)
        }
    }
}

private struct LargeFileRow: View {
    let file: DirNode
    @Binding var isOn: Bool

    var body: some View {
        let path = file.path
        let hint = JunkRules.largeFileHint(path)
        HStack(spacing: 8) {
            Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.checkbox)
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(file.name).lineLimit(1).truncationMode(.middle)
                    if let hint {
                        Badge(text: hint, color: hint.contains("don't") || hint.contains("system") ? .red : .secondary)
                    }
                }
                Text((path as NSString).deletingLastPathComponent.abbreviatingHome)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            .help(path)
            Spacer(minLength: 8)
            Text(ageText(file.modified))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .trailing)
            Text(FileSize.format(file.size))
                .font(.callout.monospacedDigit())
                .frame(width: 80, alignment: .trailing)
            Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help("Reveal in Finder")
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Explorer

struct ExplorerView: View {
    @Bindable var model: DiskScanModel
    @AppStorage("useTrash") private var useTrash = true
    @State private var pendingDelete: DirNode?

    var body: some View {
        let _ = model.revision
        if let node = model.current ?? model.result?.root {
            VStack(spacing: 0) {
                breadcrumb(node)
                Divider()
                List {
                    if let parent = node.parent {
                        Button { model.current = parent } label: {
                            Label("..", systemImage: "arrow.turn.left.up")
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach(node.children) { child in
                        row(child, parentSize: node.size)
                    }
                    if node.hiddenCount > 0 {
                        HStack {
                            Image(systemName: "ellipsis.circle").foregroundStyle(.tertiary)
                            Text("\(node.hiddenCount.formatted()) smaller items")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(FileSize.format(node.hiddenSize))
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .confirmationDialog(
                "Delete “\(pendingDelete?.name ?? "")” (\(FileSize.format(pendingDelete?.size ?? 0)))?",
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                presenting: pendingDelete
            ) { target in
                Button(useTrash ? "Move to Trash" : "Delete Permanently", role: .destructive) {
                    model.remove([target], useTrash: useTrash)
                }
            } message: { target in
                Text(target.path)
            }
        }
    }

    private func breadcrumb(_ node: DirNode) -> some View {
        var chain: [DirNode] = []
        var n: DirNode? = node
        while let x = n { chain.insert(x, at: 0); n = x.parent }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(chain.enumerated()), id: \.offset) { index, item in
                    if index > 0 { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }
                    Button(index == 0 ? item.name.abbreviatingHome : item.name) { model.current = item }
                        .buttonStyle(.plain)
                        .foregroundStyle(item === node ? .primary : .secondary)
                }
                Text("· \(FileSize.format(node.size))").foregroundStyle(.secondary).monospacedDigit()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
    }

    private func row(_ child: DirNode, parentSize: Int64) -> some View {
        let fraction = parentSize > 0 ? Double(child.size) / Double(parentSize) : 0
        return HStack(spacing: 8) {
            Image(systemName: child.isFile ? "doc.fill" : "folder.fill")
                .foregroundStyle(child.junk != nil ? .blue : .secondary)
                .frame(width: 18)
            Text(child.name).lineLimit(1).truncationMode(.middle)
            if let junk = child.junk { Badge(text: junk.kind, color: .blue) }
            Spacer(minLength: 8)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(fraction > 0.5 ? Color.orange : Color.accentColor)
                        .frame(width: max(2, geo.size.width * fraction))
                }
            }
            .frame(width: 120, height: 6)
            Text(String(format: "%.0f%%", fraction * 100))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
            Text(FileSize.format(child.size))
                .font(.callout.monospacedDigit())
                .frame(width: 80, alignment: .trailing)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !child.isFile, !child.children.isEmpty || child.hiddenCount > 0, child.junk == nil {
                model.current = child
            }
        }
        .contextMenu {
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: child.path)])
            }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(child.path, forType: .string)
            }
            Divider()
            Button(useTrash ? "Move to Trash…" : "Delete…", role: .destructive) { pendingDelete = child }
        }
        .help(child.isFile ? child.path : "\(child.path)\nClick to open")
    }
}
