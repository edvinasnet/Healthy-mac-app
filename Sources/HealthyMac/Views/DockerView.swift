import SwiftUI

struct DockerView: View {
    @Bindable var model: DockerModel
    @State private var confirmAction: DockerClient.Action?

    var body: some View {
        VStack(spacing: 0) {
            content
            Divider()
            footer
        }
        .navigationTitle("Docker")
        .toolbar {
            ToolbarItemGroup {
                Toggle("Show stopped", isOn: $model.showStopped)
                    .onChange(of: model.showStopped) { Task { await model.refresh() } }
                Button { Task { await model.refresh() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
            }
        }
        .confirmationDialog(
            "\(confirmAction?.rawValue.capitalized ?? "") \(model.selection.count) container(s)?",
            isPresented: Binding(get: { confirmAction != nil }, set: { if !$0 { confirmAction = nil } }),
            presenting: confirmAction
        ) { action in
            Button(action.rawValue.capitalized, role: .destructive) {
                model.perform(action, ids: Array(model.selection))
            }
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    @ViewBuilder
    private var content: some View {
        if !model.available {
            ContentUnavailableView("Docker CLI not found", systemImage: "shippingbox",
                                   description: Text("Install Docker Desktop, OrbStack, Colima or Rancher Desktop."))
        } else if let error = model.error {
            ContentUnavailableView {
                Label(error.daemonDown ? "Docker is not running" : "Docker error", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error.message)
            } actions: {
                if error.daemonDown { Button("Start Docker") { model.openDockerDesktop() } }
            }
        } else if !model.loaded {
            ProgressView().frame(maxHeight: .infinity)
        } else if model.containers.isEmpty {
            ContentUnavailableView("No containers", systemImage: "shippingbox",
                                   description: Text(model.showStopped ? "No containers exist." : "No running containers."))
        } else {
            Table(model.containers, selection: $model.selection) {
                TableColumn("Name") { (c: DockerContainer) in
                    HStack(spacing: 6) {
                        Circle().fill(c.isRunning ? .green : .gray).frame(width: 8, height: 8)
                        Text(c.name).lineLimit(1)
                    }
                }
                .width(min: 120, ideal: 180)
                TableColumn("Project") { (c: DockerContainer) in Text(c.project).foregroundStyle(.secondary) }
                    .width(min: 60, ideal: 100)
                TableColumn("Image") { (c: DockerContainer) in Text(c.image).lineLimit(1).truncationMode(.middle) }
                    .width(min: 100, ideal: 180)
                TableColumn("Status") { (c: DockerContainer) in Text(c.status).foregroundStyle(.secondary) }
                    .width(min: 80, ideal: 130)
                TableColumn("CPU") { (c: DockerContainer) in Text(c.cpu).monospacedDigit() }
                    .width(60)
                TableColumn("Memory") { (c: DockerContainer) in Text(c.memory).monospacedDigit().lineLimit(1) }
                    .width(min: 90, ideal: 140)
                TableColumn("Ports") { (c: DockerContainer) in
                    Text(c.ports).lineLimit(1).truncationMode(.middle).help(c.ports)
                }
            }
            .contextMenu(forSelectionType: String.self) { ids in
                let list = Array(ids)
                if !list.isEmpty {
                    Button("Stop") { model.perform(.stop, ids: list) }
                    Button("Restart") { model.perform(.restart, ids: list) }
                    Button("Start") { model.perform(.start, ids: list) }
                    Divider()
                    Button("Kill") { model.perform(.kill, ids: list) }
                    Button("Remove (force)") { model.perform(.rm, ids: list) }
                    Divider()
                    let projects = Set(list.compactMap { id in model.containers.first { $0.id == id }?.project }.filter { !$0.isEmpty })
                    ForEach(Array(projects), id: \.self) { project in
                        Button("Stop whole project “\(project)”") {
                            model.perform(.stop, ids: model.containers.filter { $0.project == project && $0.isRunning }.map(\.id))
                        }
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Text(model.status ?? "\(model.containers.filter(\.isRunning).count) running · \(model.selection.count) selected")
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Button("Stop All Running") {
                model.selection = Set(model.containers.filter(\.isRunning).map(\.id))
                confirmAction = .stop
            }
            .disabled(!model.containers.contains(where: \.isRunning))
            Button("Stop") { confirmAction = .stop }.disabled(model.selection.isEmpty)
            Button("Kill", role: .destructive) { confirmAction = .kill }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(model.selection.isEmpty)
        }
        .padding(10)
    }
}
