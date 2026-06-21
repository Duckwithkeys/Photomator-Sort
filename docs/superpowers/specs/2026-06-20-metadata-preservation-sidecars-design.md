# Metadata Preservation via XMP Sidecars — Design

Date: 2026-06-20
Status: Approved (design)

## Problem

DuckSort presents itself as preserving photo metadata, but the export pipeline
drops the app's own metadata:

- Custom tags are written as `dc:subject` keywords into per-file `.xmp` sidecars
  next to the **source** files (`XMPTaggingService`), but `PhotoSet.allFiles` is
  only `mediaFiles + editPath`. Copy/move never carries the `.xmp` sidecars, so
  tagged photos lose their tags at the destination.
- JPEG re-encode (`JPEGExportService`, routed JPEG path) copies embedded
  EXIF/IPTC via `sourceProperties`, so capture metadata survives — but the
  in-app custom tags are neither embedded in the output nor emitted as a sidecar.
- Nothing records the inspector's capture metadata (camera, lens, ISO, shutter,
  aperture, date) as a portable sidecar.

Embedded capture metadata in original files is fine; the gap is **the app's own
tag and capture metadata failing to travel with exports** — across all formats,
RAW included.

## Goals

When files are copied, moved, or exported, preserve:

1. **Custom tags** (`dc:subject` keywords) alongside every destination file.
2. **Capture metadata** (camera, lens, ISO, shutter, aperture, capture date)
   recorded in a portable sidecar.
3. Coverage for **every format including RAW** — not just re-encoded JPEGs.

Sidecars are the primary mechanism (safe for RAW, which cannot be rewritten).
Re-encoded JPEGs additionally embed keywords in-file.

## Non-goals

- Rewriting metadata inside RAW or HEIF files.
- Editing source files during export (sidecars are generated at the destination).
- A general metadata editor. This is preservation on export only.

## Approach

Unify on one component and add a sidecar post-step to every export path.

### Core component: `SidecarService` (extends `XMPTaggingService`)

`XMPTaggingService` already owns XMP read/write/merge for `dc:subject`. Extend it
rather than add a parallel writer.

New surface:

- `SidecarPayload` — value type `{ tagNames: Set<String>, capture: MetadataSnapshot }`.
- `writeSidecar(_ payload: SidecarPayload, besideDestinationFile url: URL) throws`
  — emits a sibling `.xmp` containing both:
  - `dc:subject` keyword bag (existing logic), and
  - capture metadata in standard namespaces: `tiff:Model`, `exif:LensModel`,
    `exif:FNumber`, `exif:ExposureTime`, `exif:ISOSpeedRatings`,
    `exif:DateTimeOriginal`. Fields absent from `MetadataSnapshot` are omitted.
- `embeddedKeywordProperties(_ tagNames: Set<String>) -> [CFString: Any]`
  — a CGImage properties fragment (IPTC `Keywords` plus XMP `dc:subject`) to merge
  into `destinationProperties` for the JPEG re-encode embed.

The existing in-app tag read/write path (`applyTagNames`, `readTagNames`,
`clear`) is unchanged.

### Sidecar naming

Keep the existing convention: `BASENAME.xmp` beside each destination media file
(`IMG.RAF` → `IMG.xmp`), the DAM-standard form the app already reads back. A
co-located RAW + JPEG of the same shot share one sidecar — correct, since they
carry identical tags and capture data. When the same shot is routed to different
destination folders, each folder gets its own sidecar.

### Hook points (data flow)

`PhotoLibraryViewModel` populates a tag map when building each plan; services read
capture metadata via the `MetadataReader` they already hold.

- `Plan` structs (`TransferPlan`, `JPEGExportPlan`, routed plan) gain
  `tagNames: [PhotoSet.ID: Set<String>]`, filled from `TagStore`.
- `FileTransferService` (copy/move): after each media file lands, write its
  `.xmp` at the destination.
- `RoutedTransferService` (copy/move + JPEG): same, per routed destination file.
- `JPEGExportService` (re-encode): write the `.xmp` **and** merge
  `embeddedKeywordProperties` into `destinationProperties` before
  `CGImageDestinationFinalize` (EXIF already carried via `sourceProperties`).

Sidecars are regenerated at the destination from live app state, not copied from
source. Exported tags are therefore never stale, and no source sidecar is
orphaned.

This keeps services self-contained: they receive tag names through the plan and
read capture metadata themselves — `TagStore` never reaches into an actor.

### Error handling

- **Best-effort, never fatal.** A sidecar or embed failure must never abort a
  file transfer. Failures are caught and counted.
- `TransferSummary` and `JPEGExportSummary` gain `sidecarFailures: Int`, surfaced
  to the user as a soft warning (the transfer itself still reports success).
- Tag-name escaping reuses the existing XML escape helpers.

### Edge cases

- **No tags, capture metadata only:** still write the sidecar. (Unlike the in-app
  tag flow, which deletes the sidecar when tags become empty.)
- **RAW + JPEG, same basename, same destination folder:** one shared `BASENAME.xmp`.
- **Move:** also relocate or delete any pre-existing source `.xmp` so a moved file
  leaves no orphan behind. The destination sidecar is regenerated regardless.

## Testing (TDD)

The package currently has no test target. Add a `.testTarget("DuckSortTests")`
to `Package.swift` and a `Tests/DuckSortTests/` directory as the first step.
Note: `DuckSort` is an `executableTarget`; the test target depends on it, and
the types under test (`SidecarService`, the transfer/export services, models)
must be reachable — they are `internal` today, so `@testable import DuckSort`
covers it.

Unit tests over temp directories with small fixture images:

- Tagged set exported → `.xmp` exists beside each destination file, containing the
  expected `dc:subject` entries **and** expected `exif:`/`tiff:` capture fields.
- JPEG re-encode → output JPEG's embedded properties contain the keywords, and
  embedded EXIF (e.g. camera model) survives the re-encode.
- No-tags set → sidecar still written, with capture metadata.
- Sidecar write failure (read-only destination) → transfer still succeeds and
  `sidecarFailures` increments.

## Documentation

Update `README.md` to state precisely what is preserved: custom tags and capture
metadata travel as `.xmp` sidecars on copy, move, and export across all formats;
re-encoded JPEGs also embed keywords in-file.

## Affected files

- `DuckSort/Utilities/XMPTaggingService.swift` → extended to `SidecarService`.
- `DuckSort/Utilities/FileTransferService.swift`
- `DuckSort/Utilities/RoutedTransferService.swift`
- `DuckSort/Utilities/JPEGExportService.swift`
- `DuckSort/ViewModels/PhotoLibraryViewModel.swift` (populate tag maps)
- `README.md`
- `Package.swift` (add test target)
- New `Tests/DuckSortTests/` test target and fixtures.
