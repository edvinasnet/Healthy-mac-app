import SwiftUI

struct SettingsView: View {
    @AppStorage("useTrash") private var useTrash = true

    var body: some View {
        Form {
            Section("Removal") {
                Toggle("Move files to Trash instead of deleting", isOn: $useTrash)
                Text("Files owned by root (launch daemons, helper tools, receipts) are always deleted permanently after you enter your password. No helper tool is ever installed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Permissions") {
                LabeledContent("Full Disk Access") {
                    Text(Permissions.hasFullDiskAccess ? "Granted" : "Not granted")
                        .foregroundStyle(Permissions.hasFullDiskAccess ? .green : .orange)
                }
                Button("Open Full Disk Access settings…") { Permissions.openFullDiskAccessSettings() }
                Button("Open App Management settings…") { Permissions.openAppManagementSettings() }
                Text("App Management lets HealthyMac delete other apps' bundles on macOS 13+.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .padding()
    }
}
