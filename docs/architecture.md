# Architecture

HealthyMac is a single-process SwiftUI app built with Swift Package Manager. It is not sandboxed
(an uninstaller has to read and delete other apps' files) and it never installs a helper tool.

## Source layout

```
Sources/HealthyMac/
  HealthyMacApp.swift      @main App, window + Settings scene, AppDelegate
  Core/
    Shell.swift            Runs command-line tools; runs commands as root via the admin prompt
    SafetyGuard.swift      Refuses to delete system locations and well-known parent folders
    FileSize.swift         On-disk size of files/trees; `~` path abbreviation
    Permissions.swift      Full Disk Access probe, links into System Settings
  Uninstaller/
    AppScanner.swift       Finds installed .app bundles and reads their Info.plist
    LeftoverFinder.swift   Search locations + matching rules for an app's related files
    OrphanFinder.swift     Data left by apps that are no longer installed
    Remover.swift          Quits apps, moves to Trash / deletes, falls back to admin
    UninstallerModel.swift State for the Applications and Leftover Files screens
  Processes/
    ProcessScanner.swift   ps + libproc + lsof → categorised process list; ProcessKiller
    DockerClient.swift     Wraps the docker CLI (ps, stats, stop/kill/…)
    ProcessModels.swift    State for the Processes and Docker screens
  Views/                   SwiftUI views, one per screen + shared rows/badges
```

## Layers

```
 Views (SwiftUI)          AppsView  OrphansView  ProcessesView  DockerView  SettingsView
        │ observe / call
 Models (@Observable,     UninstallerModel        ProcessModel        DockerModel
   @MainActor)
        │ Task.detached
 Engines (pure, sync)     AppScanner  LeftoverFinder  OrphanFinder   ProcessScanner  DockerClient
                          Remover                                    ProcessKiller
        │
 Core                     Shell  SafetyGuard  FileSize  Permissions
```

- **Views** hold no logic beyond presentation and confirmation dialogs.
- **Models** are `@MainActor @Observable` classes. They own UI state (lists, selection, busy
  flags) and start background work.
- **Engines** are stateless `enum`s with synchronous functions. They do blocking I/O (file
  system walks, `ps`, `lsof`, `docker`) and are always called from `Task.detached`, so the UI
  never blocks.
- **Core** has the low-level helpers shared by everything.

## Threading

The pattern is the same everywhere:

```swift
isBusy = true
Task {                                   // runs on the main actor
    let result = await Task.detached {   // runs on a background thread
        Engine.doBlockingWork()
    }.value
    self.state = result                  // back on the main actor
    isBusy = false
}
```

Exceptions:

- `Shell.runAsAdmin` runs on the main actor, because `NSAppleScript` is not thread-safe and the
  password dialog is modal anyway.
- Sizes are filled in gradually: the list appears first, then each item's size is computed in
  the background and written back, so big folders don't delay the list.
- Long-running screens (Processes every 3 s, Docker every 5 s) run a refresh loop that starts in
  `onAppear` and is cancelled in `onDisappear`, so nothing polls while the screen is hidden.
  A refresh is skipped if the previous one is still running.

## Language mode

The package uses the Swift 6 toolchain with `swiftLanguageMode(.v5)`. All UI state is on the
main actor; background closures only capture value types (`struct`s and `URL`s).

## App bundle

SwiftPM produces a bare executable. `scripts/build-app.sh` wraps it into `HealthyMac.app` with
`Resources/Info.plist` and `Resources/AppIcon.icns` and signs it. When launched as a bare
executable (`swift run`), `AppDelegate` sets the activation policy to `.regular` so a window and
Dock icon still appear.
