# Uninstaller

Three steps: find installed apps → find the files related to one app → remove the files the
user ticked. A separate scan finds data whose app is already gone.

## 1. Finding apps — `AppScanner`

- Scans `/Applications` and `~/Applications`, going up to two folders deep (so
  `/Applications/Utilities/*.app` and vendor folders such as `/Applications/Adobe X/*.app` are
  included).
- For each `.app` it reads `Info.plist` through `Bundle(url:)`: bundle identifier, display
  name, `CFBundleName`, version and executable name.
- **App Store** apps are detected by `Contents/_MASReceipt/receipt`.
- **System** apps (Safari etc.) live on the read-only sealed system volume
  (`volumeIsReadOnly`). They are shown greyed out and can't be removed.
- Any `.app` dropped on the list is loaded the same way, wherever it lives.
- App sizes are computed after the list appears (see `FileSize.of`, which adds up
  `totalFileAllocatedSize` and never follows symlinks).

## 2. Finding related files — `LeftoverFinder`

### Where it looks

Only the **top level** of each known location is listed. There is no recursive search of the
disk, which keeps it fast (well under a second) and predictable.

| User (`~/Library/…`) | System (`/Library/…` and others) |
|---|---|
| Application Support, Caches, Preferences, Preferences/ByHost | Application Support, Caches, Preferences |
| Containers, Group Containers, Application Scripts | LaunchAgents, LaunchDaemons, PrivilegedHelperTools |
| Saved Application State, HTTPStorages, WebKit, Cookies | Logs, Logs/DiagnosticReports |
| Logs, Logs/DiagnosticReports | Internet Plug-Ins, Extensions, Audio/Plug-Ins/HAL + Components |
| LaunchAgents, Internet Plug-Ins, Services | PreferencePanes, QuickLook, Spotlight, Screen Savers, Input Methods |
| PreferencePanes, QuickLook, Spotlight, Screen Savers, Input Methods | `/private/var/db/receipts` (installer receipts) |
| Per-user temp and cache folders under `/var/folders` (from `confstr`) | |

### How entries are matched

Each entry name is lowercased and has known suffixes removed (`.plist`, `.savedState`,
`.binarycookies`, `.bom`, `.log`, `.ips`, …). Then it is compared with the app:

| Confidence | Rule | Example for `com.tinyspeck.slackmacgap` |
|---|---|---|
| **Exact** | name equals the bundle id, or starts with `id.`, `id-`, `id_`, or ends with `.id`, or contains `.id.` | `com.tinyspeck.slackmacgap.plist`, `BQR82RBBHL.com.tinyspeck.slackmacgap` |
| **Exact** | a launch agent/daemon whose `Program`/`ProgramArguments[0]` is inside the app bundle, or whose `AssociatedBundleIdentifiers` contains the bundle id | `/Library/LaunchDaemons/…plist` that starts `/Applications/X.app/…` |
| **Exact** | the privileged helper that such a launch daemon starts | `/Library/PrivilegedHelperTools/com.x.helper` |
| **Name match** | the name with letters/digits only equals the app's display name, `CFBundleName` or executable name (generic names like `Electron` or `main` are ignored) | `~/Library/Application Support/Slack` |
| **Name match** | crash reports starting with `<executable>-` or `<app name>-` | `Slack-2026-01-01-….ips` |
| **Same vendor** | same first two bundle id parts (`com.docker.`), or a group container with the app's code-signing Team ID | `com.docker.socket`, `UBF8T346G9.Office` |

**Same vendor** files may belong to another app from the same developer, so they are never
ticked by default. If no other installed app shares the vendor prefix, a vendor match is
upgraded to **Name match** (example: Docker's `com.docker.socket` helper when Docker is the only
`com.docker.*` app). Very generic prefixes (`com.github.`, `io.github.`, `com.electron.`,
`com.apple.`, …) are never used as vendors.

The Team ID comes from the app's code signature (`SecStaticCodeCreateWithPath` +
`SecCodeCopySigningInformation`).

Each result records whether the current user can delete it (`isDeletableFile`). Items that
need root show a lock icon.

### Defaults in the UI

- The app bundle itself is the first row.
- Exact and Name match rows are ticked; Same vendor rows are not.
- Unticking the app bundle turns **Uninstall** into **Remove Selected**, which resets the app
  (removes its data, keeps the app).

## 3. Leftovers of uninstalled apps — `OrphanFinder`

Two kinds of evidence:

1. **Bundle-id-named folders with no app.** In the user's Application Support, Caches,
   Preferences, Containers, Group Containers, Saved State, HTTP Storage, WebKit, Cookies, Logs
   and Application Scripts:
   - The entry name is normalised: suffixes removed, a trailing `.UUID` (ByHost prefs) removed,
     and for group containers / scripts a 10-character Team ID prefix and `group.` removed.
   - It must look like reverse-DNS (`a.b.c` or longer).
   - `com.apple.*` and a few system/shared prefixes are ignored.
   - It counts as installed if it equals, is a parent of, or is a child of any installed bundle
     id, or if Launch Services (`NSWorkspace.urlForApplication(withBundleIdentifier:)`) knows an
     app for it or for any parent id with at least three parts. Launch Services also finds
     apps outside `/Applications`.
   - **Shared developer data is kept while any app from that developer is installed.** Vendors
     often share sign-in and settings between their apps (Microsoft's `UBF8T346G9.com.microsoft.oneauth`
     is used by Outlook, Teams, Office and VS Code). An entry is skipped when:
     - its group container / script folder carries the code-signing **Team ID** of an installed
       app (forms `TEAMID.id`, `group.TEAMID.id`, `TEAMID.group.id`);
     - its vendor prefix (`com.microsoft.`) matches an installed app's bundle id;
     - one of its first two parts is the **company name** of an installed app's vendor
       (`jetbrains.ps.253` while `com.jetbrains.PhpStorm` is installed).
   - Data of built-in macOS features that don't use `com.apple.` is ignored too: Shortcuts
     (`is.workflow.*`) and printing (`org.cups.*`).
2. **Broken launch jobs.** Launch agents/daemons whose program path no longer exists.

Results are grouped by identifier and **nothing is ticked**. Command-line tools also write
reverse-DNS folders, so the user decides.

## 4. Removing — `Remover`

```
selected URLs
   │  SafetyGuard.isSafe?  ── no ──► reported as "Blocked by safety guard"
   ▼
quit the app if its bundle is included  (terminate → wait up to 3 s → forceTerminate)
   ▼
user pass (background thread), for each item:
   - launch agent plist  → `launchctl bootout gui/<uid> <plist>` first
   - deletable by user?  → move to Trash (default) or delete permanently
   - permission error / not deletable → put on the admin list
   ▼
admin pass (only if the list isn't empty) — ONE password prompt:
   launchctl bootout system '<daemon.plist>' …; /bin/rm -rf '<p1>' '<p2>' …
   ▼
check each path again with lstat → removed / failed (with reason)
```

- Files removed through the admin pass are deleted permanently; there is no way to move
  root-owned files into the user's Trash.
- After removal the app is rescanned; if the bundle is gone it disappears from the list.
- The result alert lists failures and, for "Operation not permitted", reminds the user about
  Full Disk Access / App Management.
