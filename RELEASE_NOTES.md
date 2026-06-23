# DuckSort v1.2.4 (Swift Concurrency & Performance Optimizations & JPEG Export Cleanups)

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
