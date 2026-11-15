import SwiftUI

struct OrphansView: View {
    @Bindable var model: UninstallerModel
    @AppStorage("useTrash") private var useTrash = true
    @State private var confirming = false

    var body: some View {
        VStack(spacing: 0) {
            content
            Divider()
            footer
        }
        .navigationTitle("Leftover Files")
        .toolbar {
            ToolbarItem {
                Button { model.scanOrphans() } label: { Label("Scan", systemImage: "arrow.clockwise") }
                    .disabled(model.isScanningOrphans)
            }
        }
        .task { if !model.orphansScanned { model.scanOrphans() } }
    }

    @ViewBuilder
    private var content: some View {
        if model.isScanningOrphans {
            ProgressView("Scanning ~/Library for data of uninstalled apps…").frame(maxHeight: .infinity)
        } else if model.orphans.isEmpty {
            ContentUnavailableView("No leftovers found", systemImage: "checkmark.seal",
                                   description: Text("Nothing obviously belongs to an app that is no longer installed."))
        } else {
            List {
                Text("These look like data of apps that are no longer installed. Nothing is preselected — review before removing. Command-line tools also store data here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                ForEach(model.orphans) { group in
                    Section {
                        ForEach(group.items) { item in
                            LeftoverRow(item: item, isOn: .member(item.id, of: $model.orphanChecked))
                        }
                    } header: {
                        HStack {
                            Toggle("", isOn: groupBinding(group)).labelsHidden().toggleStyle(.checkbox)
                            Text(group.id).font(.headline.monospaced())
                            Text(group.reason).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            Spacer()
                            Text(FileSize.format(group.size)).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func groupBinding(_ group: OrphanGroup) -> Binding<Bool> {
        let ids = Set(group.items.map(\.id))
        return Binding(
            get: { !ids.isEmpty && ids.isSubset(of: model.orphanChecked) },
            set: { on in
                if on { model.orphanChecked.formUnion(ids) } else { model.orphanChecked.subtract(ids) }
            })
    }

    private var footer: some View {
        HStack {
            Button("None") { model.orphanChecked = [] }
            Text("\(model.orphanChecked.count) selected · \(FileSize.format(model.orphanCheckedSize))")
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Spacer()
            Toggle("Move to Trash", isOn: $useTrash)
            Button("Remove Selected", role: .destructive) { confirming = true }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(model.orphanChecked.isEmpty || model.isRemoving)
                .confirmationDialog("Remove \(model.orphanChecked.count) item(s)?", isPresented: $confirming) {
                    Button(useTrash ? "Move to Trash" : "Delete Permanently", role: .destructive) {
                        model.removeCheckedOrphans(useTrash: useTrash)
                    }
                }
        }
        .padding(10)
    }
}
