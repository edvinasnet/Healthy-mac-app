import SwiftUI

struct ProcessesView: View {
    @Bindable var model: ProcessModel
    @State private var pending: KillRequest?

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()
            table
            Divider()
            footer
        }
        .navigationTitle("Processes")
        .searchable(text: $model.search, placement: .toolbar, prompt: "Command, PID, port, folder")
        .toolbar {
            ToolbarItemGroup {
                Toggle(isOn: $model.autoRefresh) { Label("Live", systemImage: "dot.radiowaves.left.and.right") }
                    .help("Refresh every 3 seconds")
                Button { Task { await model.refresh() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
            }
        }
        .confirmationDialog(pending?.title ?? "", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), presenting: pending) { req in
            Button(req.force ? "Force Kill" : "Terminate", role: .destructive) { model.perform(req) }
        } message: { req in
            Text(names(for: req.pids))
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    private var filterBar: some View {
        HStack(spacing: 12) {
            Picker("Filter", selection: $model.filter) {
                ForEach(ProcFilter.allCases) { f in
                    Text("\(f.rawValue) \(model.count(f))").tag(f)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Spacer()
            let t = model.totals(model.filter)
            Text("CPU \(String(format: "%.0f", t.cpu))% · RAM \(FileSize.format(t.mem))")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
            if model.isRefreshing { ProgressView().controlSize(.small) }
        }
        .padding(10)
    }

    private var table: some View {
        Table(model.visible, selection: $model.selection, sortOrder: $model.sortOrder) {
            TableColumn("Name", value: \.name) { (p: ProcInfo) in
                HStack(spacing: 6) {
                    Image(systemName: p.category.symbol)
                        .foregroundStyle(p.category.color)
                        .frame(width: 16)
                    Text(p.name).lineLimit(1)
                }
                .help(p.category.rawValue)
            }
            .width(min: 140, ideal: 190)

            TableColumn("PID", value: \.pid) { (p: ProcInfo) in
                Text(String(p.pid)).monospacedDigit()
            }
            .width(56)

            TableColumn("CPU %", value: \.cpu) { (p: ProcInfo) in
                Text(String(format: "%.1f", p.cpu))
                    .monospacedDigit()
                    .foregroundStyle(p.cpu > 50 ? .red : .primary)
            }
            .width(56)

            TableColumn("Memory", value: \.rssKB) { (p: ProcInfo) in
                Text(FileSize.format(p.memBytes)).monospacedDigit()
            }
            .width(76)

            TableColumn("Ports") { (p: ProcInfo) in
                Text(p.portsText).monospacedDigit().foregroundStyle(.orange)
            }
            .width(min: 50, ideal: 80)

            TableColumn("Uptime", value: \.uptime) { (p: ProcInfo) in
                Text(p.uptimeText).monospacedDigit()
            }
            .width(66)

            TableColumn("Folder") { (p: ProcInfo) in
                Text(p.cwdDisplay).lineLimit(1).truncationMode(.head).help(p.cwd ?? "")
            }
            .width(min: 80, ideal: 170)

            TableColumn("User", value: \.user) { (p: ProcInfo) in
                Text(p.user).foregroundStyle(.secondary)
            }
            .width(min: 50, ideal: 70)

            TableColumn("Command", value: \.command) { (p: ProcInfo) in
                Text(p.command)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                    .help(p.command)
            }
        }
        .contextMenu(forSelectionType: Int32.self) { ids in
            if !ids.isEmpty {
                let pids = Array(ids)
                Button("Terminate") { pending = KillRequest(pids: pids, force: false, tree: false) }
                Button("Terminate with Children") { pending = KillRequest(pids: pids, force: false, tree: true) }
                Button("Force Kill") { pending = KillRequest(pids: pids, force: true, tree: false) }
                Button("Force Kill with Children") { pending = KillRequest(pids: pids, force: true, tree: true) }
                Divider()
                Button("Copy Command") { copy(pids.compactMap { pid in model.processes.first { $0.pid == pid }?.command }) }
                if pids.count == 1, let p = model.processes.first(where: { $0.pid == pids[0] }) {
                    if let cwd = p.cwd {
                        Button("Reveal Folder in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: cwd)])
                        }
                    }
                    ForEach(p.ports, id: \.self) { port in
                        Button("Open http://localhost:\(port)") {
                            if let url = URL(string: "http://localhost:\(port)") { NSWorkspace.shared.open(url) }
                        }
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Text(model.status ?? "\(model.visible.count) shown · \(model.selection.count) selected")
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            let pids = Array(model.selection)
            Button("Terminate") { pending = KillRequest(pids: pids, force: false, tree: false) }
                .disabled(pids.isEmpty)
            Button("Kill Tree") { pending = KillRequest(pids: pids, force: false, tree: true) }
                .disabled(pids.isEmpty)
                .help("Terminate selected processes and everything they spawned")
            Button("Force Kill", role: .destructive) { pending = KillRequest(pids: pids, force: true, tree: true) }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(pids.isEmpty)
                .help("SIGKILL selected processes and their children")
        }
        .padding(10)
    }

    private func names(for pids: [Int32]) -> String {
        let list = pids.prefix(8).compactMap { pid in model.processes.first { $0.pid == pid } }
            .map { "\($0.name) (\($0.pid))" }
        return list.joined(separator: ", ") + (pids.count > 8 ? " …" : "")
    }

    private func copy(_ lines: [String]) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }
}
