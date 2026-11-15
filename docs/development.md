# Development

## Build and run

```bash
swift build                 # debug build
swift run                   # run without an app bundle (permissions attach to your terminal)
./scripts/build-app.sh      # release .app in build.noindex/HealthyMac.app
```

The output folder ends in `.noindex` so Spotlight doesn't show a second HealthyMac next to the
installed one. See the README for installing and signing.

## App icon

The icon is drawn in code, so it can be changed without design tools:

```bash
swift scripts/make-icon.swift
```

This renders every size of the iconset with Core Graphics (emerald rounded square following
Apple's 824/1024 icon grid, white heart from the classic parametric heart curve, pulse line),
runs `iconutil`, and writes `Resources/AppIcon.icns` plus a 1024 px `Resources/AppIcon.png`
preview. Colours and shape are at the top of `drawIcon(in:)`.

## Debugging tips

- **Scanners without the UI:** the engines (`AppScanner`, `LeftoverFinder`, `OrphanFinder`,
  `ProcessScanner`, `DockerClient`) are plain synchronous functions. Compile them with a small
  `main.swift` that prints results:
  ```bash
  cd Sources/HealthyMac
  swiftc -swift-version 5 -o /tmp/hm-selftest /path/to/main.swift \
    Core/*.swift Uninstaller/AppScanner.swift Uninstaller/LeftoverFinder.swift \
    Uninstaller/OrphanFinder.swift Uninstaller/Remover.swift \
    Processes/ProcessScanner.swift Processes/DockerClient.swift
  ```
  Only call read-only functions (`scan`, `find`, `list`) from such a harness.
- **Layout problems:** if content is cut off at the top *and* bottom, some view is asking for
  more height than the window has. Print the `NSWindow.contentView` hierarchy and look for a
  frame taller than the window. Watch out for `.fixedSize(horizontal: false, vertical: true)`
  on text inside sidebars, and for `HSplitView` inside `NavigationSplitView` (both broke the
  layout on macOS 26).

## Extending

- **New leftover location:** add a `(path, kind)` row to `LeftoverFinder.searchRoots`. The
  location automatically becomes protected in `SafetyGuard` (the folder itself can never be
  deleted, only its entries).
- **New AI / dev tool:** add its executable name to `aiTokens` (or another category set) in
  `ProcessScanner.swift`, or a distinctive part of its command line to `aiSubstrings`.
- **New Docker runtime:** add its CLI path to `DockerClient.binary` candidates and, if needed,
  to `Shell.extendedPATH`.
- **New sidebar screen:** add a case to `SidebarItem` in `ContentView.swift`, a model if it
  needs state, and a view; follow the `Task.detached` pattern from
  [architecture.md](architecture.md).
