# Privileges and safety

## No helper tool

Many uninstallers install a privileged helper (`SMJobBless` / `SMAppService` launch daemon)
that runs as root all the time. HealthyMac doesn't. Instead:

- Everything the current user can do is done directly with `FileManager` and `kill()`.
- When something needs root (a launch daemon, a helper tool, an installer receipt, a root
  process), HealthyMac collects **all** such items for the current action and asks for the
  administrator password **once**:

```swift
// Core/Shell.swift
NSAppleScript(source: "do shell script \"<command>\" with administrator privileges")
```

This is the standard macOS authorization dialog. The command runs once as root and nothing
stays installed or running afterwards. Paths are single-quoted for `/bin/sh` (`Shell.quote`)
and the AppleScript string is escaped, so file names with spaces or quotes are safe.

Commands that can run as root:

| Feature | Command |
|---|---|
| Remove root-owned files | `launchctl bootout system '<daemon.plist>'` (daemons only), then `/bin/rm -rf '<path>' …` |
| Kill root processes | `/bin/kill -TERM|-KILL <pid> …` |

## Safety guard — `SafetyGuard.isSafe`

Every path passes through this check before deletion, in both the finder and the remover
(defence in depth). A path is refused when:

- it has fewer than 3 path components (`/`, `/Library`, `/Users`, …);
- it is one of the protected paths: `/System`, `/Library`, `/Applications`,
  `/Applications/Utilities`, `/Users`, `/Users/Shared`, `/usr`, `/usr/local`, `/bin`, `/sbin`,
  `/etc`, `/var`, `/tmp`, `/opt`, `/private/…`, `/private/var/db/receipts`, `/var/folders`,
  `/Volumes`, the home folder and its standard subfolders (`Library`, `Documents`, `Desktop`,
  `Downloads`, `Applications`, `Movies`, `Music`, `Pictures`, `Public`, `.Trash`,
  `Library/Mobile Documents`, `Library/CloudStorage`);
- it is **any search location itself** (for example `~/Library/Caches`): only entries
  *inside* them can be removed;
- it is a parent of the home folder;
- it is under `/System/`, `/bin/`, `/sbin/`, `/etc/`, or `/usr/` (except `/usr/local/`);
- it is HealthyMac's own bundle.

Other safety measures:

- Apps on the sealed system volume are marked protected and the Uninstall button is disabled.
- "Same vendor" leftovers and all orphan items are never ticked by default.
- Everything destructive (uninstall, remove, kill, Docker kill/stop) needs a confirmation
  dialog.
- Moving to Trash is the default, so user-level removals can be undone.
- Symlinks are deleted as links; their targets are never followed (sizes use `lstat`
  semantics too).

## macOS privacy permissions (TCC)

Not being sandboxed isn't enough on modern macOS. Two permissions matter:

| Permission | Why | Without it |
|---|---|---|
| **Full Disk Access** | read and delete other apps' containers and protected data | some leftovers are invisible or fail with "Operation not permitted" |
| **App Management** (macOS 13+) | modify or delete other apps' bundles | removing an `.app` may fail |

- Full Disk Access is detected by trying to open `~/Library/Application Support/com.apple.TCC/TCC.db`,
  which only works with that permission. The sidebar shows a banner when it's missing, and the
  check runs again whenever the app becomes active.
- Settings (⌘,) has buttons that open both panes in System Settings.
- TCC also applies to root: a command run through the admin prompt still counts as HealthyMac,
  so these permissions are needed even for admin removals.
- Permissions are tied to the code signature. Ad-hoc builds get a new signature every build,
  so macOS forgets the permissions; sign with a stable identity (`SIGN_IDENTITY`, see the
  README) to keep them.

## What HealthyMac does not do

- No network access, telemetry or update checks.
- Nothing runs in the background after you quit; refresh loops stop when a screen is hidden.
- No recursive scan of the whole disk; only known locations are listed.
