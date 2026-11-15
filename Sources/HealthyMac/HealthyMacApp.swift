import AppKit
import SwiftUI

@main
struct HealthyMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var uninstaller = UninstallerModel()
    @State private var processes = ProcessModel()
    @State private var docker = DockerModel()

    var body: some Scene {
        WindowGroup("HealthyMac") {
            ContentView(uninstaller: uninstaller, processes: processes, docker: docker)
                .frame(minWidth: 1000, minHeight: 620)
        }

        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare SwiftPM executable (`swift run`).
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
