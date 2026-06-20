[README.md](https://github.com/user-attachments/files/29156847/README.md)
# Photomator Sort

Photomator Sort is a lean macOS photo sorting companion app built with SwiftUI. Its first job is simple: point it at a photoshoot folder or SD card, find all supported photo files, detect which ones have Photomator edit sidecars, and help move or copy selected photo sets to a destination folder.

The app is intentionally small right now. The code is organized so future features like tag profiles, metadata-aware exporting, and token-based renaming can be added without rewriting the core scanning and transfer flow.

## Current MVP

The app currently supports:

- Choosing a source folder with the macOS folder picker.
- Recursively scanning the selected folder and its subfolders.
- Grouping files into one `PhotoSet` when they share the same folder and base filename.
- Detecting Photomator-edited images by matching `.photo-edit` files.
- Filtering the grid by:
  - All Photos
  - Edited Only
  - Unedited Only
- Selecting photo sets in the grid.
- Choosing a destination folder.
- Copying or moving all underlying files for the selected photo sets.
- Exporting selected photo sets as compiled JPEG files.
- Token-based JPEG naming presets.
- Optional smart export folders by capture date, camera model, and lens model.
- Per-file progress reporting during copy, move, and JPEG export operations.
- Fast tag profiles with number-key shortcuts.
- XMP sidecar writing for selected photo sets.
- Persistent preferences for last source folder, destination folder, and filter mode.

For example, these files are treated as one photo set:

```text
DSCF0622.RAF
DSCF0622.HIF
DSCF0622.photo-edit
```

The `.photo-edit` file marks the set as edited.

## Supported File Types

The scanner currently recognizes:

- `.RAF`
- `.RAW`
- `.HIF`
- `.JPG`
- `.JPEG`
- `.photo-edit`

Extension matching is case-insensitive.

## Project Structure

```text
PhotomatorSort/
  Models/
    PhotoSet.swift
    PhotoFilterRule.swift
    FileGroupingResult.swift

  Utilities/
    FileScanner.swift
    FileTransferService.swift
    FileManager+Directory.swift

  ViewModels/
    PhotoLibraryViewModel.swift

  Views/
    ContentView.swift
    HeaderBar.swift
    PhotoGridView.swift
    TransferFooter.swift
    EmptyLibraryView.swift
    Components/
      PhotoSetCell.swift
      ThumbnailView.swift
    Utilities/
      FolderPanel.swift

  PhotomatorSortApp.swift
```

## Core Architecture

### Models

`PhotoSet` is the central data model. It represents one logical photo asset made from multiple physical files:

- `baseName`: display and grouping name, such as `DSCF0622`
- `mediaFiles`: matching image files
- `editPath`: matching `.photo-edit` file, if present
- `hasEdit`: true when `editPath` exists
- `isSelected`: grid selection state

`PhotoFilterRule` owns the filtering behavior for All, Edited Only, and Unedited Only.

### Scanner

`FileScanner` is an actor that performs filesystem scanning away from SwiftUI state. It recursively walks the selected source folder, checks file extensions, and groups media/edit files by their standardized path without the extension.

This matters because camera filenames often repeat across folders. Grouping by folder plus base name avoids accidentally merging different shoots that both contain something like `DSCF0001.RAF`.

Photomator `.photo-edit` items are accepted as regular files, directories, or packages. In real Photomator folders they can appear as ZIP-backed regular files.

### View Model

`PhotoLibraryViewModel` is the main `@MainActor` state container for the app. It owns:

- the selected source folder
- the selected destination folder
- the scanned photo sets
- the current filter
- selection counts
- scan and transfer progress text
- user-facing errors

It calls `FileScanner` for scans and `FileTransferService` for copy/move operations.

### Transfer Service

`FileTransferService` is an actor that copies or moves selected photo sets to the destination folder. It transfers every file in each selected `PhotoSet`, including RAW/HEIF/JPEG variants and the `.photo-edit` file.

If a destination filename already exists, the service creates a numbered filename instead of overwriting the existing file.

### Tag Profiles

`TagProfile` defines the current fast-tagging profiles:

- Red: `1`
- Orange: `2`
- Yellow: `3`
- Green: `4`
- Blue: `5`
- Purple: `6`
- Clear Tags: `0`

The tag bar applies the chosen profile to every selected photo set. Tags are written through `TaggingUtility` into XMP sidecars next to the media files. The sidecar includes standard `dc:subject` keyword entries and a color label field for apps that read XMP labels.

This is intentionally isolated from the photo scanner and transfer code so future hierarchical keyword profiles can replace or extend the built-in color profiles.

### Preferences

`UserPreferences` stores lightweight app state in `UserDefaults`:

- last source folder path
- last destination folder path
- last selected photo filter

When the app starts, it restores those values and automatically rescans the previous source folder when available.

### JPEG Export Service

`JPEGExportService` creates compiled JPEG exports from the selected photo sets. It uses the fastest available preview source in each set, preferring JPEG, then HEIF, then RAW.

JPEG exports support token-based naming presets:

- Original + Sequence
- Date + Original + Sequence
- Camera + Original + Sequence

The export service can also create smart subfolders from ImageIO metadata:

- capture date
- camera model
- lens model

Metadata is read by `MetadataReader`, which extracts EXIF/TIFF fields through ImageIO. If metadata is missing, the export falls back to safe names such as `Unknown Date`, `Unknown Camera`, or `Unknown Lens`.

## Interface

The main window has three areas:

1. Header toolbar: source picker, scan summary, filter picker, and selection controls.
2. Photo grid: responsive SwiftUI grid with Quick Look thumbnails.
3. Footer: status text, destination picker, Copy Selected, Move Selected, Export JPEGs, naming presets, smart folder toggles, and progress reporting.
4. Tag bar: one-click tag profiles plus number-key shortcuts for selected photos.

Thumbnails use Quick Look through `QLThumbnailGenerator`, which keeps preview loading lightweight and lets macOS handle RAW/HEIF rendering where possible.

## Building & Packaging

Photomator Sort is a standard Swift Package that can be opened directly in Xcode or built via the command line.

### Requirements
- macOS 14.0 or later
- Xcode 15.0 or later (Xcode 27.0 beta supported)

### Local Development Build
To compile the debug executable:
```bash
swift build
```

To run a fast syntax/type check on all source files:
```bash
swiftc -parse PhotomatorSort/**/*.swift
```

### Packaging a Release Bundle (`.app`)
We provide an automated script to build and package the optimized application into a standalone macOS `.app` bundle with the default dark app icon:
```bash
./package_app.sh
```
This script will:
1. Compile the app in **Release** configuration.
2. Construct the standard macOS app bundle structure (`PhotomatorSort.app`).
3. Embed the compiled resource bundles and the generated `AppIcon.icns`.
4. Codesign the bundle with an ad-hoc signature.

### Creating a DMG Installer (`.dmg`)
To package the `.app` bundle into a compressed, read-only disk image ready for redistribution:
```bash
./create_dmg.sh
```
This packages the `.app` bundle alongside a symlink to `/Applications` for standard drag-and-drop installation.

---

## Performance & Memory Optimizations

To handle large photoshoots efficiently (1,000+ RAW/HEIF sets), the app implements several key optimizations:

- **Parallelized Metadata Scanning**: Metadata extraction (`MetadataReader`) uses a bounded concurrency `TaskGroup` (capping at 8 concurrent tasks) during photoshoot loading, reducing folder scan times by up to 8x.
- **Fast, Zero-Allocation Date Parsing**: Replaced heavy and thread-unsafe `DateFormatter` configurations with a high-performance custom EXIF date parser, eliminating CPU/memory overhead during import scans.
- **Bounded Image Cache**: The high-resolution preview loader (`LargeImageLoader`) is backed by a bounded `NSCache` restricted to at most **50** pre-decoded images or **200MB** of raw pixel data (computed as `width * height * 4` bytes), preventing unbounded RAM growth during long culling sessions.
- **Cooperative Cancellation**: Detached background tasks for image preloading and rendering monitor `Task.isCancelled` to immediately abort unused decoding work when navigating rapidly between photos.

