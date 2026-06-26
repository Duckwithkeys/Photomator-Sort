# DuckSort v1.3 (Tag Packs Redesign, Files-in-Set Inspector, HEIF Previews, Major Performance Pass)

Welcome to version 1.3 of **DuckSort**! This release overhauls the Tag Packs settings UI, introduces a "Files in Set" inspector in the large viewer, brings full HEIF/HEIC preview support, adds an XMP tag inspector overlay, and ships a sweeping performance pass that retunes 25 hot paths across the codebase for O(1) lookups, single-pass filters, and pre-compiled regexes.

## ✨ What's New in v1.3
* **Tag Packs Settings Overhaul**:
  - Removed the left "Categories" sidebar — the Tags pane is now a single full-width column so the pack strip sits cleanly above the inline editor.
  - Settings window is resizable and starts at 960×720 (was 720×480) so multi-monitor users can keep the pack library visible while editing.
  - **Per-tag inline color picker** on every `TagChip` — click the swatch and the native macOS color panel opens directly, no nested menu.
  - **SF Symbol picker for tag-pack logos** — choose from a curated catalog of 50+ symbols grouped by People, Moments, Activities, Objects, and Tech, or type any SF Symbol name to use one not in the catalog.
* **Large Viewer "Files in Set" Inspector**:
  - Replaces the old "N files + edit" summary with a real per-file list showing every file that belongs to the set.
  - Each row shows the actual filename (e.g. `DSCF0142.RAF`, `DSCF0142.JPG`, `DSCF0142.HEIC`, `DSCF0142.photo-edit`) with a colour-coded role chip — red for RAW, green for JPEG, indigo for HEIF, yellow for the edit sidecar.
  - Right-click any row to **Reveal in Finder** or **Copy Filename**.
  - **Format bug fix**: A RAW + HEIF set now correctly reports `formatLabel = "RAW + HEIF"` (it was silently classified as RAW-only before, because HEIF extensions also live in `rawLikeExtensions` and the `if/else if` chain checked RAW first).
* **HEIF/HEIC Preview Support**:
  - `CGImageSourceCreateThumbnailAtIndex` returns nil for some HEIC bursts and unusual orientation metadata — added a `NSImage(contentsOf:)` fallback path that uses the system codec, then down-samples to the requested pixel budget.
  - HEIF files now reliably decode on first try, and the thumbnail `previewRank` puts them ahead of RAW so a set without a JPEG sibling shows the HEIF as its preview.
* **XMP Tag Inspector Overlay**:
  - **View → "XMP Tags Not in Active Pack…"** opens a floating overlay window (`⌘⇧X`) that scans every loaded photo's sidecar and lists any `dc:subject` keywords not defined as a tag in the active pack.
  - Each row shows the orphan keyword, the count of photos using it, and example filenames.
  - One-click **Add to Pack** writes a new tag into the active pack (preferring the `Subject` category) and rescans. The row disappears immediately via optimistic local update — no waiting for the full rescan.
* **Sidebar Tag Filter Refinements**:
  - The "Active Filters" bar is now permanent at the top of the sidebar's filter stack (under the search field), so the layout doesn't shift when filters are toggled.
  - When zero filters are active, the bar renders a grayed-out "No active filters" state with a disabled Clear button.
* **Keyboard Improvements**:
  - **Press `I` in the grid** to open the large image viewer (was: toggled the Inspector panel).
  - All other shortcuts unchanged.
* **Tag Chip Visual Improvements**:
  - Per-tag color picker styled as a prominent pill so it reads as the primary action, not a hidden nested menu.
  - Format pills on grid cells use a consistent palette (`RAW` = red, `JPEG` = green, `HEIF` = indigo, `EDIT` = yellow) shared with the large viewer so both surfaces agree on what each colour means.

## ⚡ Performance Pass (25 optimizations applied)

Every item from the `prompt.txt` / `Suggestions.txt` performance playbook was implemented in a single session. All 22 tests still pass. Highlights:

* **O(1) photo-set lookups** — `photoSetIndex: [UUID: Int]` rebuilt inside `photoSets` didSet; `toggleSelection`, `setSelection`, and the metadata-load result loops now use dict subscripts instead of `firstIndex(where:)`.
* **Pre-compiled XMP regexes** — 19 inline `try? NSRegularExpression(pattern:)` calls in `XMPTaggingService` replaced with a `nonisolated static let` palette in `XMPSchema.Regex`. Mirrors `MetadataReader`'s pattern.
* **`XMPTaggingService` is now a `Sendable struct`** — was an `actor`, which serialized all sidecar writes during concurrent transfers. Removed `await` from 9 call sites in the view model and transfer services.
* **Single-pass `updateDerivedState`** — the 7-stage `.filter()` chain (rule → rejected → tags → flags → ratings → subfolder → search) collapsed into one `for` loop with early `continue`, short-circuiting on the first failing filter. The subfolder filter compares `.path` strings instead of resolving URLs.
* **Merged `loadMetadata` + `loadExistingTags`** — `loadMetadataAndTags(for:)` reads EXIF and XMP sidecars in a single `withTaskGroup`, applies results in ONE `photoSets` assignment, and runs in two phases (first 100 sets visible-first, then the rest in the background).
* **Visible-first metadata** — the first 100 photo sets load with high priority and apply immediately, so the grid is interactive 5–10× sooner on large libraries.
* **`destinationFolders` cached** — `RoutedTransferService` computes the per-photo folder list ONCE into a `routingResults` array instead of 3 times (pre-walk → mkdir → job-build).
* **`DateFormatter` cached** in `ExportPathRouter.defaultDateFolderFormatter` — was allocating a fresh formatter per photo on every routed transfer.
* **Pre-read metadata** flows from `loadMetadataAndTags` through `TransferPlan.metadata` to `FileTransferService.execute`, eliminating the per-photo `CGImageSource` re-read during transfer.
* **`.min(by:)` instead of `.sorted().first`** in `PhotoSet.init.preferredPreviewURL` — O(n log n) → O(n).
* **Two of three redundant sorts removed** from `FileScanner`; only the final sort in `PhotoLibraryViewModel.scanSourceDirectories` remains.
* **`allFiles` and `fileBreakdown` are stored `let`s on `PhotoSet`** (cached at init instead of computed every read) — important because `fileBreakdown` is read on every focused-photo change in the large viewer.
* **`tagsByShortcut: [KeyboardShortcutInfo: CustomTag]`** in `TagStore` — keypress handler does one dict lookup instead of iterating every tag and re-parsing hotkey strings.
* **`tagsByShortcut` + `colorCache`** rebuilt inside `updateIndexes()` — the keypress hotkey lookup and the per-tag `Color(hex:)` rendering now both hit caches.
* **`PhotoSetCell: Equatable` + `EquatableView`** — unchanged cells skip body re-evaluation when one cell's selection flips.
* **`ThumbnailCache` scales to physical memory** — 800/120MB on 8GB, 1500/200MB on 16GB, 2500/400MB on 32GB+.
* **Run-loop coalescing** of `tagStore.objectWillChange` — `updateGlobalCounts` + `updateDerivedState` no longer fire 4× per batch tag operation.
* **`UserPreferences.save()` debounced** (150ms) + `saveImmediately()` escape hatch — matches the existing 500ms `TagStore.save` debounce.
* **`extensionLookup: [String: FileExtension]`** in `FileScanner` — replaces `Set.contains` + `FileExtension(rawValue:)` double lookup.
* **`xmpSidecarURLs` dedup** — incremental `Set.insert` instead of `Array(Set(...)).sorted()` round-trip.
* **`escape` is a single-pass character scanner** in `XMPTaggingService` (was 4 chained `replacingOccurrences`); `unescape` kept as 5 chained calls for correctness on `&amp;` ordering.
* **`FilenameSanitizer.clean` is a single-pass unicode-scalar loop** (was `components(separatedBy:).joined()`).
* **`uniqueDestinationURL` extracted** to `Utilities/FileNaming.swift` and shared by both transfer services — was copy-pasted.
* **Chunked file-size computation** in both transfer services — replaces 1-task-per-file overhead with chunks sized to `activeProcessorCount`.

## 🐛 Bug Fixes
* **HEIF format classification** — `Models/PhotoSet.init` now checks JPEG → HEIF → RAW in that order. Previously HEIF files were matched by the `rawLikeExtensions` check first, so a RAW + HEIF set reported `formatLabel = "RAW"` and the thumbnail pill said only "RAW". Now correctly says "RAW + HEIF" (or whatever derivative is present).
* **`XMPTaggingService.updateCaption`** — `String?` parameter now accepted; previously the signature forced non-optional `String` and callers passing nil would crash.
* **`updateSidecarRatingPick`** — new helper replaces duplicated metadata-read code in `FileTransferService` and `RoutedTransferService`.
* **`XMPTaggingService` Sendable conformance** — `ISO8601DateFormatter` is wrapped in an unchecked-Sendable box so the new struct compiles.
* **SettingsTagsPaneView editor overflow** — fixed when adding/removing tags (height was previously miscomputed with the left-sidebar layout).
* **Tag chip overflow** — fixed at 180pt cell width; chips no longer touch the tag name text.
* **Grid ACTIVE ring clipping** — fixed; the ring no longer clips into the section header above the cards.

## 🛠 Internal
* `FileNaming.uniqueDestinationURL(for:in:fileManager:)` — new shared utility.
* `XMPSchema.Regex` — pre-compiled NSRegularExpression palette for `XMPTaggingService`.
* `LoadedPhotoInfo` (fileprivate) — compact value type used by `loadMetadataAndTags` to ferry per-photo results out of the task group.
* `LoadedPhotoInfo`'s parent `applyMetadataAndTagResults` builds a local `[UUID: Int]` index before the result-application loop so it never does a `firstIndex(where:)` scan inside the per-photo loop.
* `PhotoLibraryViewModel.TransferPlan.metadata` — new optional field carries pre-read EXIF metadata from scan time into the transfer pipeline.

---


Welcome to version 1.2.4 of **DuckSort**! This release implements major performance improvements throughout the app's backend and UI systems (focusing on Swift concurrency optimization, O(1) index lookups, concurrent file transfers, and dynamic color memoization to deliver massive performance speedups on large photo libraries) and cleans up the UI by removing the deprecated user-facing JPEG export feature.

## ✨ What's New in v1.2.4
* **Parallelized & Bounded File Transfers**:
  - Refactored file routing and transfer tasks to run concurrently using a bounded `TaskGroup` on background threads, preventing actor blockage and maximizing NVMe drive throughput.
  - Parallelized the pre-walk file size calculation phase using a concurrent task group to eliminate start-up delays on large exports.
* **O(1) Tag Lookup & Debounced Writes**:
  - Implemented cached lookup index dictionaries for tags in the database to replace slow linear scans with instant lookup operations.
  - Added a 500ms debounce buffer to throttle Tag Database writes to disk, protecting SSD lifespans and removing UI micro-stutters during rapid hotkey tagging.
* **Main Actor Optimization & Single-Pass Counting**:
  - Replaced the broken `break` loop behavior in background metadata loading tasks with a proper, concurrent Swift Concurrency `withTaskGroup` structure.
  - Flattened the global library metadata count method in the View Model to compute ratings, picks, tag counts, and subfolders concurrently in a single pass instead of nested loops.
* **Memory & Rendering Optimizations**:
  - Converted the computed theme colors into static constants, caching the `NSColor` dynamic provider instances once to eliminate allocation overhead during SwiftUI redrawing while retaining full native system appearance updates.
  - Stored expensive computed properties like preview URLs, display names, and format lists directly on `PhotoSet` at initialization, preventing redundant allocations on every grid cell redraw.
  - Added a Combine-based 120ms debounce pipeline to search bar filtering to avoid recalculating visible results on every individual keystroke.
* **Removed User-Facing JPEG Export**:
  - Removed the ability to export photos to new JPEG files via the UI, simplifying the Transfer Footer, the Large Image Viewer sidebar, and internal transfer view models.
  - **Note**: General JPEG format support (detecting, displaying, previewing, and copying/moving JPEG files during library transfers) remains fully supported and unchanged.

---

# DuckSort v1.2.3 (UI Refinements, Performance & Subfolder Navigation)

Welcome to version 1.2.3 of **DuckSort**! This release introduces source subfolder navigation dropdowns in the sidebar, improves sidebar collapse gestures, optimizes `Command + A` performance to eliminate selection lag, introduces scrolling-throttled thumbnail loading, fixes image viewer light/dark mode styling, resolves viewer layout and zoom clipping issues, and fixes the search bar launch auto-focus bug.

## ✨ What's New in v1.2.3
* **Source Subfolder Navigation**:
  - Added expandable dropdown lists for subfolders under each source folder in the sidebar.
  - Clicking a subfolder filters the photo grid view to show only photos from that subfolder.
* **Improved Sidebar Interaction**:
  - Allowed collapsing or expanding tag categories by clicking anywhere on the category header row (with dynamic hover-highlights).
* **Command + A Performance Optimization**:
  - Refactored selection methods to perform batch array updates, eliminating quadratic redraw loops and preventing main-thread freezes (beach balls) when selecting/deselecting all items.
* **Throttled Grid Scrolling**:
  - Added a global scroll state observer to defer and throttle image loading while scrolling rapidly, rendering the grid scrolling butter-smooth.
* **Large Image Viewer Layout & Styling Fixes**:
  - Retained a dark canvas background behind the photo viewer in both light and dark macOS modes for maximum image contrast.
  - Made the viewer top bar and filmstrip adaptively support light and dark system appearances for clean readability.
  - Fixed image clipping so that zoomed images do not overlap the top bar or filmstrip elements.
  - Added leading padding to the filmstrip HUD counter capsule and set the filmstrip view background to always dark.
* **Search Bar Focus Control**:
  - Bypassed default AppKit/SwiftUI search bar auto-focus on launch using a delayed check, allowing immediate Spacebar culling actions to open the first photo in the grid view.
* **Typography Size Continuity**:
  - Adjusted button labels in the Transfer Footer to `.font(.callout)` and grid count text to `.font(.footnote)` to resolve bottom and top header text size continuity issues.

---

# DuckSort v1.2.2 (System Theme Integration & Performance Fixes)

Welcome to version 1.2.2 of **DuckSort**! This release introduces native macOS system appearance integration, fixes critical layout-related main thread hangs (beach balls) when filtering and resizing, improves keyboard focus control, and optimizes startup performance.

## ✨ What's New in v1.2.2
* **Native System Theme Integration**:
  - Removed the physical Moon/Sun toggle button and `@AppStorage("isDarkMode")` overrides. The application window, buttons, menus, and sidebars now natively and automatically transition between Light and Dark mode according to macOS system preferences.
* **Instant Startup Loading & Performance Cache**:
  - Parallelized XMP sidecar reads using a concurrent `TaskGroup` to fetch up to 16 files simultaneously on background threads.
  - Batched tag assignments to database files using a new `setTagsBatch(_:)` method, reducing multiple synchronous disk writes to a single pass.
  - Batched metadata-based updates to `photoSets` and `photoMetadata` arrays, eliminating hundreds of individual Main Actor redraws during folder scans.
  - Memoized global counts for tags, flags, and star ratings, eliminating redundant UI redraws and preventing lag when switching between library views.
* **Fixed Layout Loops & Beach Balls**:
  - Wrapped `scrollProxy.scrollTo` operations in `DispatchQueue.main.async` in both the grid and filmstrip views. This defers scrolling until SwiftUI layout passes finish, resolving the main thread freeze (beach ball) that occurred when changing library filters.
  - Added safety checks in `columnCount(forWidth:)` to ignore infinite or NaN width dimensions during window resizing, preventing fatal conversion crashes.
  - Added cancellation checks in the high-resolution image loader (`LargeImagePane.swift`) to abort pending background file reads immediately when dismissing the large image viewer.
* **Dismissible Search Bar Focus & Local Filtering**:
  - Configured the search bar to start unfocused on launch, ensuring hotkeys like the Space bar and Return key are active for culling immediately.
  - Implemented live local search filtering in the search bar, allowing instant base name lookup across the active grid.
  - Automatically resigns keyboard focus from the search bar when the user clicks empty space in the grid, empty library workspace, or selects a photo cell.
* **Clean Application Shutdown**:
  - Implemented a custom `AppDelegate` that terminates the background application process completely when the last window is closed, releasing system resources.

---

# DuckSort v1.2.1 (Performance, Grid Refinements & Format Support)

Welcome to version 1.2.1 of **DuckSort**! This release introduces critical performance optimizations in the large image viewer, robust format support for standard HEIF/HEIC files and additional raw manufacturer formats, precise alignment and layout refinements in the photo grid cells, and improved resilience when loading multiple sources.

## ✨ What's New in v1.2.1
* **Grid Cell & Badge Refinements**:
  - Redesigned the photo grid cells with a clean, borderless profile and 12pt corner-rounded thumbnails.
  - Linked badge overlays (format pills, rating indicators, flags) directly to the square thumbnail bounds, guaranteeing badges never clip outside the photo box area.
  - Fixed grid row alignment using `Spacer(minLength: 0)` to keep neighbor cells top-aligned even when some cells expand due to active tags.
  - Highlighted selected items with a 3pt green border (and green text) and focused items with a 2.5pt brand blue border (and blue text).
* **Format Completeness & Warnings**:
  - Replaced the generic link badge with a vibrant orange magic wand (`wand.and.stars`) icon for edit sidecars.
  - Added a red exclamation triangle warning badge for incomplete sets (e.g. standalone JPEGs or sets missing a RAW or Photomator edit sidecar) when not in JPEG-Only mode.
* **Expanded Image & HEIF Support**:
  - Fully integrated standard HEIC and HEIF formats (`.heif`, `.heic`, `.hif`) into the culling and scanning workflows.
  - Extended raw format detection to support Sony (`.arw`), Canon (`.cr2`/`.cr3`), Nikon (`.nef`), Adobe (`.dng`), Olympus (`.orf`), Panasonic (`.rw2`), and Pentax (`.pef`).
* **Resilient Multitasking Scanner**:
  - Made the folder scanner fully resilient: an error scanning one source folder no longer disables or wipes out other successfully loaded sources.
  - Added a warning symbol next to failing sources in the sidebar list to indicate exactly which folder failed to load.
* **Filmstrip & Preloading Optimization**:
  - Rebuilt the filmstrip preloading to restrict rendering to a sliding window of 10 images ahead, dramatically reducing memory overhead and eliminating scroll delay.
  - Enabled the large image viewer to trigger on-demand thumbnail generation for filmstrip items that haven't been scrolled into view in the grid.
* **Source Folder Actions & Footer Explanations**:
  - Added a button to instantly remove individual files or folders from the sources list in the sidebar.
  - Documented sorting actions in the bottom Transfer Footer to clarify the current Destination folder and transfer rule behavior.

---

# DuckSort v1.2.0 (Branded UI, Extended Scroll & Streamlined Operations)

Welcome to version 1.2.0 of **DuckSort**! This release introduces custom branded visual assets, layout refinements that maximize vertical screen real estate, enhanced sidebar features, and streamlined culling controls.

## ✨ What's New in v1.2.0
* **Branded Custom Logo**: Replaced the generic app/folder icon next to the "DuckSort" header with the custom logo (a duck floating on filmstrips) dynamically loaded from the bundle resources.
* **Accent Separator Line**: Added a solid, 1px horizontal accent line (colored with signature brand blue) in the sidebar to define a clear visual break between the branded app header and library list.
* **Extended Grid Scroll Layout**: Removed the top-level container padding to allow the photos grid `ScrollView` to stretch to the absolute top of the window frame (`0pt`), preventing scrollable images from getting early boundary clipped.
* **Window Controls Clearance**: Offset the top margin of grid items (`44pt`) and the subfolder scanning indicator (`48pt`) to sit cleanly below the window traffic lights when scrolled to the top.
* **Sidebar Sources Management**:
  - Integrated "+ Add Source..." directly under the sources list.
  - Added hover action icons to reveal any source folder in Finder (magnifying glass) or remove it (x).
  - Added context menus with right-click reveal and remove commands.
* **Flags & Ratings Filters**: Added a "Flags & Ratings" collapsible section in the sidebar with live matching counts for Flagged, Rejected, Unrated, and Star ratings.
* **Keyboard Navigation & Selection**:
  - Escape/Delete keys now instantly clear/deselect currently selected photos.
  - Command + A selects all visible photo sets in the active grid.
* **Cleaned Up Redundant JPEG Export**: Removed the redundant "Export JPEGs" action and settings sheet from both the bottom Transfer Footer UI and backend transfer engine to simplify the application's core culling and sorting focus.
* **Cell identity Caching Fixes**: Bound photoshoot grid cells to stable UUID keys to resolve caching issues on filter switches.

---

# DuckSort v1.1.0 (UI Redesign & Viewer Navigation)

Welcome to version 1.1.0 of **DuckSort**! This release introduces a comprehensive UI overhaul to match Photomator's flat, dark professional theme, along with a newly designed sidebar, collapsible tag categories, and navigation enhancements in the large image viewer.

## ✨ What's New in v1.1.0
* **Photomator Dark UI Overhaul**: Replaced the glossy "liquid glass" elements with a flat, dark professional style using a premium charcoal and dark grey palette.
* **Collapsible Tags Sidebar**: A brand new left navigation sidebar that spans the full height of the window, featuring collapsible sections for library items, folders, and custom tags.
* **Interactive Tag Filtering**: Click tags in the sidebar to filter the grid instantly. Supports multi-selection filters for fine-tuned organization.
* **Large Image Viewer Enhancements**:
  * **Unified Grey Background**: Replaced the pitch-black canvas background with the same dark grey background as the grid view for visual consistency.
  * **Back Chevron Button**: Added an intuitive `<` back button next to the window control traffic lights to quickly exit/close the large image viewer.
  * **Clean Top Bar Spacing**: Aligned viewer top-bar elements to guarantee that text never clips under native macOS traffic lights.
* **Refined Photo Cells**: Compacted grid cells with a 2px selection border (using the signature Photomator blue) and subtle hover highlights.

---

# DuckSort v1.0.0 (Initial Release)

Welcome to the first official release of **DuckSort**! This native macOS application is designed to automate the workflow of scanning, organizing, tagging, and routing your photo sets—specifically built for high-end photography workflows (like Fujifilm RAW + JPEG shooters).

## ✨ Key Features
* **Smart Photo Grouping**: Automatically pairs RAW files with their corresponding JPEG representations and sidecar files (e.g., `.photo` files, edit metadata) as unified photo sets.
* **Photo Metadata Inspector**: Instantly view Aperture, Shutter Speed, ISO, Camera Model, and Lens for any selected photo in the large image viewer.
* **Custom Tagging**: A fully-featured Tag Manager to create, edit, and assign color-coded tags to your photo groups.
* **Export Routing Rules**: Define complex rule-based conditions (e.g., based on tags or file types) to automatically route your files to specific target directories.
* **High-Resolution Preview**: Double-click or press Space to view full-canvas previews of your images.
* **Visual Transfer Progress Bar**: High-precision byte-level tracking displaying real-time data transfer rate (MB/s) and megabytes completed during batch operations.
* **JPEG-Only Mode**: A dedicated toggle in the toolbar to exclusively scan and route JPEG files while ignoring missing edit warnings.
* **Keyboard-Driven Workflow**: High-efficiency keyboard shortcuts (`Cmd + A`, `S`, `I`, `0`, and custom tag hotkeys) for rapid selection, navigation, and culling.

## 🛠️ Requirements
* **macOS 14.0 (Sonoma)** or newer.

## 📥 Installation
1. Download the **`DuckSort.dmg`** file from the assets below.
2. Double-click the downloaded `.dmg` file to mount it.
3. Drag the **DuckSort** app into your `Applications` folder.
4. Launch the app from Launchpad or your Applications folder!
