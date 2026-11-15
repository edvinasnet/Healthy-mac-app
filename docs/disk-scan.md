# Disk Scan

Finds what fills the disk, especially folders that tools generate and can regenerate
(dependency installs, build output, download caches), which pile up across many projects.

## Scope

| Scope | Walks | Shown as |
|---|---|---|
| **Home** | your home folder | real paths |
| **Entire Disk** | `/System/Volumes/Data`, the writable data volume (users, apps, `/Library`, `/private`, `/opt`, `/usr/local`, system-managed assets) | firmlinked paths such as `/Users/…`, `/Applications/…` |
| **Folder…** | any folder you pick | real paths |

The read-only, sealed system volume isn't scanned: it can't be changed and is the same on
every Mac.

## One pass — `DiskScanner.scan`

The walk uses BSD `fts` (`fts_open` / `fts_read`) with:

- `FTS_PHYSICAL`: symlinks are never followed;
- `FTS_XDEV`: stays on one volume (external drives, network mounts, Time Machine and
  other APFS volumes are skipped);
- `FTS_NOCHDIR`: doesn't change the process working directory.

Sizes are **allocated** sizes (`st_blocks × 512`), so sparse files (Docker's disk image) and
iCloud files that aren't downloaded count only what they really use. Hard-linked files
(`st_nlink > 1`) are counted once, tracked by inode.

### Bounded memory

A full tree of millions of entries would take gigabytes, so the tree is pruned while walking:

- When a folder finishes (post-order `FTS_DP`), child folders under **1 MB** are merged
  into the parent's `hiddenCount` / `hiddenSize` ("N smaller items" in the Explorer).
- Files under **25 MB** are never stored as nodes, only added to their folder's size.
- Inside a detected generated folder (for example `node_modules`) no nodes are created at
  all; sizes are summed into that folder.

Measured on a home folder with 3.4 million files: about 90 s, 37 MB peak memory.

### Unreadable folders

`FTS_DNR` / `FTS_ERR` (permission denied, mostly protected app data without Full Disk Access)
are counted and shown as "N items unreadable". The folder still closes correctly, because
`fts` returns `FTS_DNR` in place of `FTS_DP`.

### Progress and cancel

Every 2,000 entries the scanner checks a thread-safe cancel flag and, at most every 150 ms,
reports files, bytes and the current folder to the UI. A cancelled scan keeps the partial
results.

## Generated & caches — `JunkRules`

### Project folders (by name + marker file)

A folder name alone isn't enough (`build` and `target` are common names), so most rules
also need a **marker** next to or inside the folder:

| Folder | Needs | Kind |
|---|---|---|
| `node_modules` | `package.json` next to it | node_modules |
| `.next` | `package.json` / `next.config.*` | Next.js build |
| `.nuxt`, `.output` | `nuxt.config.*` | Nuxt build |
| `.svelte-kit` | `svelte.config.js` / `package.json` | SvelteKit build |
| `.angular` | `angular.json` | Angular cache |
| `.expo` | `app.json` / `package.json` | Expo cache |
| `target` | `Cargo.toml` or `pom.xml` | Rust / Maven build |
| `build`, `.gradle` | `build.gradle(.kts)` / `settings.gradle(.kts)` | Gradle build |
| `build`, `.dart_tool` | `pubspec.yaml` | Flutter / Dart build |
| `Pods` | `Podfile` | CocoaPods |
| `.build` | `Package.swift` | SwiftPM build |
| `cmake-build-*` | `CMakeLists.txt` | CMake build |
| `.venv`, `venv`, `env`, `.virtualenv` | `pyvenv.cfg` **inside** | Python virtualenv |
| `.turbo`, `.parcel-cache`, `.pytest_cache`, `.mypy_cache`, `.ruff_cache`, `.tox`, `.terraform`, `.zig-cache`, `DerivedData` | nothing (the name is specific enough) | various |

### Global caches (by path)

`~/.npm/_cacache`, Yarn, pnpm store/cache, Bun, pip, uv, Homebrew, Gradle caches, Maven
`~/.m2/repository`, Cargo registry, Go modules and build cache, CocoaPods, Xcode DerivedData,
Archives and iOS DeviceSupport, simulator caches, Playwright/Puppeteer browsers, JetBrains
caches, and AI model stores (`~/.cache/huggingface`, `~/.ollama/models`, labelled as large
re-downloads).

Only folders of **1 MB or more** are listed. Once a folder matches, nothing inside it is
matched again (no `node_modules` inside `node_modules`).

### Using the list

- Each row shows the project folder, the kind, the **last-modified age** (orange after 30
  days) and the size. Hover for the restore hint ("Restore with npm install"…).
- Filter by kind, sort by size or oldest first.
- **Select unused > 30 days** ticks folders whose own modification date is older than 30 days,
  usually projects you haven't touched.
- Nothing is ticked automatically.

## Large files

Files of **100 MB or more**, largest first, with hints for known types:

- `Docker.raw`: shrink with `docker system prune` or in Docker settings; don't delete it.
- System-managed assets under `/System/…` (simulator runtimes): remove them in Xcode →
  Settings → Components. The safety guard blocks deleting them here.
- Ollama / Hugging Face models, iOS backups, simulator data, disk images, firmware, archives.

## Explorer

Browse the pruned tree: folders sorted by size, a bar and percentage of the parent, a
breadcrumb to jump back. Click a folder to open it. The context menu offers Reveal in Finder,
Copy Path and Move to Trash / Delete. Generated folders are marked with their kind and aren't
expanded (their contents weren't stored).

## Deleting

All three tabs use the same `Remover` as the uninstaller (see
[privileges-and-safety.md](privileges-and-safety.md)): safety guard, Trash or permanent delete,
one admin prompt for root-owned items. After deletion the item is removed from the tree and its
size is subtracted from every parent folder, so totals stay correct without rescanning.

Moving `node_modules` to the Trash is instant (a rename), but space is freed only after you
empty the Trash. Choose **Delete Permanently** to free it immediately.
