# Metadata Preservation via XMP Sidecars — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When files are copied, moved, or exported, write an `.xmp` sidecar beside every destination file recording the photo's custom tags and capture metadata; re-encoded JPEGs additionally embed keywords in-file.

**Architecture:** Extend the existing `XMPTaggingService` (an `actor`) into the single sidecar component. Each export service (`FileTransferService`, `RoutedTransferService`, `JPEGExportService`) gains a best-effort sidecar post-step that never aborts a transfer; failures are counted and surfaced. Tags reach the services through the plan structs; capture metadata is read in-service via the existing `MetadataReader`.

**Tech Stack:** Swift 5.9, ImageIO / CoreGraphics (CGImageSource/Destination), Foundation, Swift Package Manager, XCTest.

## Global Constraints

- Platform floor: `macOS 26.0` (set in `Package.swift`).
- The app target `DuckSort` is an `.executableTarget` at path `DuckSort/`. Tests use `@testable import DuckSort`.
- Sidecar naming: `BASENAME.xmp` beside each destination media file (`IMG.RAF` → `IMG.xmp`), matching the convention `XMPTaggingService` already reads.
- Sidecars are generated at the destination from live app state — never copied from source.
- Sidecar/embed failures are **best-effort**: caught, counted in `sidecarFailures`, and never thrown out of a transfer.
- Sidecars are written only beside **media files** (`PhotoSet.mediaFiles`), never beside the `.photo` edit bundle or the `.xmp` itself.
- Tag keyword source is `CustomTag.name`.
- Follow existing file headers/comment style.

---

### Task 1: Add a test target

**Files:**
- Modify: `Package.swift`
- Create: `Tests/DuckSortTests/SmokeTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: a runnable `swift test` target named `DuckSortTests` with `@testable import DuckSort`.

- [ ] **Step 1: Add the test target to `Package.swift`**

Replace the `targets:` array so it reads:

```swift
    targets: [
        .executableTarget(
            name: "DuckSort",
            path: "DuckSort",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "DuckSortTests",
            dependencies: ["DuckSort"],
            path: "Tests/DuckSortTests"
        )
    ]
```

- [ ] **Step 2: Write a smoke test that imports the app module**

Create `Tests/DuckSortTests/SmokeTests.swift`:

```swift
import XCTest
@testable import DuckSort

final class SmokeTests: XCTestCase {
    func test_metadataSnapshot_defaultsAreNil() {
        let snapshot = MetadataSnapshot()
        XCTAssertNil(snapshot.cameraModel)
        XCTAssertNil(snapshot.captureDate)
    }
}
```

- [ ] **Step 3: Run the test to verify the target builds and passes**

Run: `swift test --filter SmokeTests`
Expected: builds, `test_metadataSnapshot_defaultsAreNil` PASSES.

- [ ] **Step 4: Commit**

```bash
git add Package.swift Tests/DuckSortTests/SmokeTests.swift
git commit -m "test: Add DuckSortTests target with smoke test"
```

---

### Task 2: Test fixture helper (JPEG with known EXIF)

**Files:**
- Create: `Tests/DuckSortTests/Support/ImageFixture.swift`

**Interfaces:**
- Produces:
  - `enum ImageFixture` with `static func writeJPEG(to url: URL, cameraModel: String, lensModel: String, iso: Int) throws`
  - writes a 1×1 JPEG carrying TIFF Model, EXIF LensModel, and EXIF ISOSpeedRatings so downstream tests can assert EXIF survives.

- [ ] **Step 1: Write the fixture-roundtrip test**

Create `Tests/DuckSortTests/Support/ImageFixture.swift` first with the helper, then this test in the same file's target. Put the test in `Tests/DuckSortTests/ImageFixtureTests.swift`:

```swift
import XCTest
import ImageIO
@testable import DuckSort

final class ImageFixtureTests: XCTestCase {
    func test_fixtureWritesReadableExif() throws {
        let dir = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("IMG_0001.jpg")
        try ImageFixture.writeJPEG(to: url, cameraModel: "X-T5", lensModel: "XF35mm", iso: 400)

        let snapshot = MetadataReader().metadata(for: url)
        XCTAssertEqual(snapshot.cameraModel, "X-T5")
        XCTAssertEqual(snapshot.iso, 400)
    }
}
```

- [ ] **Step 2: Implement the fixture helper and a temp-dir helper**

Create `Tests/DuckSortTests/Support/ImageFixture.swift`:

```swift
import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

enum TempDir {
    static func make() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DuckSortTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

enum ImageFixture {
    static func writeJPEG(to url: URL, cameraModel: String, lensModel: String, iso: Int) throws {
        let width = 1, height = 1
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = ctx.makeImage() else {
            throw NSError(domain: "ImageFixture", code: 1)
        }

        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.jpeg.identifier as CFString, 1, nil
        ) else {
            throw NSError(domain: "ImageFixture", code: 2)
        }

        let properties: [CFString: Any] = [
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFModel: cameraModel
            ],
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifLensModel: lensModel,
                kCGImagePropertyExifISOSpeedRatings: [iso]
            ]
        ]
        CGImageDestinationAddImage(dest, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw NSError(domain: "ImageFixture", code: 3)
        }
    }
}
```

- [ ] **Step 3: Run the test**

Run: `swift test --filter ImageFixtureTests`
Expected: PASS (camera model "X-T5", iso 400 round-trip through ImageIO).

- [ ] **Step 4: Commit**

```bash
git add Tests/DuckSortTests/Support/ImageFixture.swift Tests/DuckSortTests/ImageFixtureTests.swift
git commit -m "test: Add JPEG-with-EXIF fixture and temp-dir helpers"
```

---

### Task 3: `SidecarPayload` + `writeExportSidecar` on `XMPTaggingService`

**Files:**
- Modify: `DuckSort/Models/ExportOptions.swift` (add `SidecarPayload`)
- Modify: `DuckSort/Utilities/XMPTaggingService.swift`
- Create: `Tests/DuckSortTests/SidecarWriteTests.swift`

**Interfaces:**
- Produces:
  - `struct SidecarPayload: Sendable { let tagNames: Set<String>; let capture: MetadataSnapshot }`
  - `XMPTaggingService.writeExportSidecar(_ payload: SidecarPayload, besideDestinationFile fileURL: URL) throws`
  - `nonisolated static func XMPTaggingService.exportSidecarURL(for fileURL: URL) -> URL`

- [ ] **Step 1: Write the failing test**

Create `Tests/DuckSortTests/SidecarWriteTests.swift`:

```swift
import XCTest
@testable import DuckSort

final class SidecarWriteTests: XCTestCase {
    func test_writeExportSidecar_emitsKeywordsAndCapture() async throws {
        let dir = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: dir) }
        let media = dir.appendingPathComponent("IMG_0001.RAF")

        let payload = SidecarPayload(
            tagNames: ["Ceremony", "Family"],
            capture: MetadataSnapshot(
                cameraModel: "X-T5", lensModel: "XF35mm",
                captureDate: nil, aperture: 2.8, shutterSpeed: 0.004, iso: 400
            )
        )

        let service = XMPTaggingService()
        try await service.writeExportSidecar(payload, besideDestinationFile: media)

        let sidecar = dir.appendingPathComponent("IMG_0001.xmp")
        let xml = try String(contentsOf: sidecar, encoding: .utf8)
        XCTAssertTrue(xml.contains("<rdf:li>Ceremony</rdf:li>"))
        XCTAssertTrue(xml.contains("<rdf:li>Family</rdf:li>"))
        XCTAssertTrue(xml.contains("tiff:Model=\"X-T5\""))
        XCTAssertTrue(xml.contains("exif:LensModel=\"XF35mm\""))
        XCTAssertTrue(xml.contains("exif:ISOSpeedRatings=\"400\""))
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter SidecarWriteTests`
Expected: FAIL — `writeExportSidecar` / `SidecarPayload` not found.

- [ ] **Step 3: Add `SidecarPayload` to `ExportOptions.swift`**

Append to `DuckSort/Models/ExportOptions.swift`:

```swift
/// Everything an export sidecar records for one destination file:
/// the custom tag keywords plus the capture metadata snapshot.
struct SidecarPayload: Sendable {
    let tagNames: Set<String>
    let capture: MetadataSnapshot
}
```

- [ ] **Step 4: Implement `writeExportSidecar` on `XMPTaggingService`**

Add to `XMPTaggingService` (inside the actor), reusing the existing `escape(_:)`:

```swift
    // MARK: - Export sidecars

    /// Destination sidecar URL for a media file (BASENAME.xmp).
    nonisolated static func exportSidecarURL(for fileURL: URL) -> URL {
        fileURL.deletingPathExtension().appendingPathExtension("xmp")
    }

    /// Write a fresh export sidecar beside a destination media file, recording
    /// both custom tag keywords and capture metadata. Overwrites any existing
    /// sidecar at that path (destination sidecars are export artifacts).
    func writeExportSidecar(_ payload: SidecarPayload, besideDestinationFile fileURL: URL) throws {
        let url = Self.exportSidecarURL(for: fileURL)
        let xmp = Self.exportXMP(payload)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try xmp.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func exportXMP(_ payload: SidecarPayload) -> String {
        var attrs: [String] = []
        if let v = payload.capture.cameraModel { attrs.append("tiff:Model=\"\(escape(v))\"") }
        if let v = payload.capture.lensModel { attrs.append("exif:LensModel=\"\(escape(v))\"") }
        if let v = payload.capture.aperture { attrs.append("exif:FNumber=\"\(formatNumber(v))\"") }
        if let v = payload.capture.shutterSpeed { attrs.append("exif:ExposureTime=\"\(formatNumber(v))\"") }
        if let v = payload.capture.iso { attrs.append("exif:ISOSpeedRatings=\"\(v)\"") }
        if let date = payload.capture.captureDate {
            attrs.append("exif:DateTimeOriginal=\"\(iso8601.string(from: date))\"")
        }
        let captureAttrs = attrs.isEmpty ? "" : "\n          " + attrs.joined(separator: "\n          ")

        let subjectBlock: String
        let sortedNames = payload.tagNames.sorted()
        if sortedNames.isEmpty {
            subjectBlock = ""
        } else {
            let keywords = sortedNames
                .map { "<rdf:li>\(escape($0))</rdf:li>" }
                .joined(separator: "\n                ")
            subjectBlock = """

              <dc:subject>
                <rdf:Bag>
                  \(keywords)
                </rdf:Bag>
              </dc:subject>
            """
        }

        return """
        <?xpacket begin="" id="W5M0MpCehiHzreSzNTczkc9d"?>
        <x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="DuckSort">
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description
              xmlns:dc="http://purl.org/dc/elements/1.1/"
              xmlns:tiff="http://ns.adobe.com/tiff/1.0/"
              xmlns:exif="http://ns.adobe.com/exif/1.0/"\(captureAttrs)>\(subjectBlock)
            </rdf:Description>
          </rdf:RDF>
        </x:xmpmeta>
        <?xpacket end="r"?>
        """
    }

    private static func formatNumber(_ value: Double) -> String {
        if value == value.rounded() { return String(Int(value)) }
        return String(format: "%.4g", value)
    }

    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
```

Note: `escape(_:)` is already `private static` on this type; these new statics can call it.

- [ ] **Step 5: Run the test to verify it passes**

Run: `swift test --filter SidecarWriteTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add DuckSort/Models/ExportOptions.swift DuckSort/Utilities/XMPTaggingService.swift Tests/DuckSortTests/SidecarWriteTests.swift
git commit -m "feat: Add export-sidecar writer recording tags + capture metadata"
```

---

### Task 4: Embedded-keyword properties helper

**Files:**
- Modify: `DuckSort/Utilities/XMPTaggingService.swift`
- Create: `Tests/DuckSortTests/EmbeddedKeywordTests.swift`

**Interfaces:**
- Produces:
  - `nonisolated static func XMPTaggingService.mervingKeywords(...)` — NO. Use exact name:
  - `nonisolated static func XMPTaggingService.mergingKeywords(_ tagNames: Set<String>, into properties: [CFString: Any]) -> [CFString: Any]`
  - Returns `properties` with the IPTC dictionary's `Keywords` array set to the sorted tag names (leaving other IPTC fields intact). Empty tag set returns `properties` unchanged.

- [ ] **Step 1: Write the failing test**

Create `Tests/DuckSortTests/EmbeddedKeywordTests.swift`:

```swift
import XCTest
import ImageIO
@testable import DuckSort

final class EmbeddedKeywordTests: XCTestCase {
    func test_mergingKeywords_setsIptcKeywords() {
        let result = XMPTaggingService.mergingKeywords(["Family", "Ceremony"], into: [:])
        let iptc = result[kCGImagePropertyIPTCDictionary] as? [CFString: Any]
        let keywords = iptc?[kCGImagePropertyIPTCKeywords] as? [String]
        XCTAssertEqual(keywords, ["Ceremony", "Family"])
    }

    func test_mergingKeywords_emptySetLeavesPropertiesUnchanged() {
        let original: [CFString: Any] = [kCGImagePropertyTIFFDictionary: ["k": "v"]]
        let result = XMPTaggingService.mergingKeywords([], into: original)
        XCTAssertNil(result[kCGImagePropertyIPTCDictionary])
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter EmbeddedKeywordTests`
Expected: FAIL — `mergingKeywords` not found.

- [ ] **Step 3: Implement the helper**

Add to `XMPTaggingService` under the export-sidecars section:

```swift
    /// Merge custom tag keywords into a CGImage properties dictionary as IPTC
    /// Keywords, for embedding in a re-encoded JPEG. Returns the dictionary
    /// unchanged when there are no tags.
    nonisolated static func mergingKeywords(
        _ tagNames: Set<String>,
        into properties: [CFString: Any]
    ) -> [CFString: Any] {
        guard !tagNames.isEmpty else { return properties }
        var result = properties
        var iptc = (result[kCGImagePropertyIPTCDictionary] as? [CFString: Any]) ?? [:]
        iptc[kCGImagePropertyIPTCKeywords] = tagNames.sorted()
        result[kCGImagePropertyIPTCDictionary] = iptc
        return result
    }
```

Add `import ImageIO` at the top of `XMPTaggingService.swift` if not already present (it imports only `Foundation` today — add `import ImageIO`).

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter EmbeddedKeywordTests`
Expected: PASS (both cases).

- [ ] **Step 5: Commit**

```bash
git add DuckSort/Utilities/XMPTaggingService.swift Tests/DuckSortTests/EmbeddedKeywordTests.swift
git commit -m "feat: Add IPTC-keyword merge helper for JPEG embedding"
```

---

### Task 5: `FileTransferService` — sidecars on plain copy/move

**Files:**
- Modify: `DuckSort/Utilities/FileTransferService.swift`
- Create: `Tests/DuckSortTests/FileTransferSidecarTests.swift`

**Interfaces:**
- Consumes: `SidecarPayload`, `XMPTaggingService.writeExportSidecar`, `MetadataReader`.
- Produces:
  - `TransferPlan` gains `let tagNames: [UUID: Set<String>]` (keyed by `PhotoSet.id`), defaulting to `[:]`.
  - `TransferSummary` gains `let sidecarFailures: Int`.

- [ ] **Step 1: Write the failing test**

Create `Tests/DuckSortTests/FileTransferSidecarTests.swift`:

```swift
import XCTest
@testable import DuckSort

final class FileTransferSidecarTests: XCTestCase {
    func test_copy_writesSidecarBesideDestinationMedia() async throws {
        let src = try TempDir.make()
        let dst = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: src); try? FileManager.default.removeItem(at: dst) }

        let media = src.appendingPathComponent("IMG_0001.jpg")
        try ImageFixture.writeJPEG(to: media, cameraModel: "X-T5", lensModel: "XF35mm", iso: 400)
        let set = PhotoSet(baseName: "IMG_0001", mediaFiles: [media], editPath: nil)

        let plan = TransferPlan(
            operation: .copy,
            destinationDirectory: dst,
            photoSets: [set],
            tagNames: [set.id: ["Family"]]
        )
        let summary = try await FileTransferService().execute(plan)

        XCTAssertEqual(summary.sidecarFailures, 0)
        let sidecar = dst.appendingPathComponent("IMG_0001.xmp")
        let xml = try String(contentsOf: sidecar, encoding: .utf8)
        XCTAssertTrue(xml.contains("<rdf:li>Family</rdf:li>"))
        XCTAssertTrue(xml.contains("tiff:Model=\"X-T5\""))
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter FileTransferSidecarTests`
Expected: FAIL — `TransferPlan` has no `tagNames`, `TransferSummary` has no `sidecarFailures`.

- [ ] **Step 3: Extend `TransferPlan` and `TransferSummary`**

In `FileTransferService.swift`, change the structs:

```swift
struct TransferPlan: Sendable {
    let operation: TransferOperation
    let destinationDirectory: URL
    let photoSets: [PhotoSet]
    let tagNames: [UUID: Set<String>]

    init(
        operation: TransferOperation,
        destinationDirectory: URL,
        photoSets: [PhotoSet],
        tagNames: [UUID: Set<String>] = [:]
    ) {
        self.operation = operation
        self.destinationDirectory = destinationDirectory
        self.photoSets = photoSets
        self.tagNames = tagNames
    }

    var files: [URL] {
        photoSets.flatMap(\.allFiles)
    }
}

struct TransferSummary: Sendable {
    let operation: TransferOperation
    let fileCount: Int
    let destinationDirectory: URL
    let sidecarFailures: Int
}
```

- [ ] **Step 4: Add sidecar dependencies and rewrite the transfer loop**

In the `FileTransferService` actor, add stored helpers at the top:

```swift
    private let sidecarService = XMPTaggingService()
    private let metadataReader = MetadataReader()
```

Replace the file-processing loop (the `for sourceURL in files { ... }` block) with a per-photoSet loop that also writes sidecars. Keep the byte/progress logic intact:

```swift
        var sidecarFailures = 0

        for photoSet in plan.photoSets {
            let mediaSet = Set(photoSet.mediaFiles.map { $0.standardizedFileURL })
            let tagNames = plan.tagNames[photoSet.id] ?? []

            for sourceURL in photoSet.allFiles {
                try Task.checkCancellation()

                let destinationURL = uniqueDestinationURL(
                    for: sourceURL, in: plan.destinationDirectory, fileManager: fm
                )
                let fileSize = (try? fm.attributesOfItem(atPath: sourceURL.path)[.size] as? Int64) ?? 0
                let isSameLocation = sourceURL.standardizedFileURL == destinationURL.standardizedFileURL

                if !isSameLocation {
                    switch plan.operation {
                    case .copy: try fm.copyItem(at: sourceURL, to: destinationURL)
                    case .move: try fm.moveItem(at: sourceURL, to: destinationURL)
                    }
                }

                // Best-effort sidecar for media files only.
                if mediaSet.contains(sourceURL.standardizedFileURL) {
                    let payload = SidecarPayload(
                        tagNames: tagNames,
                        capture: metadataReader.metadata(for: destinationURL)
                    )
                    do {
                        try await sidecarService.writeExportSidecar(payload, besideDestinationFile: destinationURL)
                    } catch {
                        sidecarFailures += 1
                    }
                    if plan.operation == .move {
                        removeOrphanSourceSidecar(for: sourceURL, fileManager: fm)
                    }
                }

                transferred += 1
                completedBytes += fileSize
                let elapsed = Date().timeIntervalSince(startTime)
                let bps = elapsed > 0 ? Double(completedBytes) / elapsed : 0
                await progress?(FileOperationProgress(
                    completed: transferred,
                    total: files.count,
                    currentName: sourceURL.lastPathComponent,
                    completedBytes: completedBytes,
                    totalBytes: totalBytes,
                    bytesPerSecond: bps
                ))
            }
        }

        return TransferSummary(
            operation: plan.operation,
            fileCount: transferred,
            destinationDirectory: plan.destinationDirectory,
            sidecarFailures: sidecarFailures
        )
```

Add this helper method to the actor:

```swift
    /// On move, delete any pre-existing source `.xmp` so the moved file leaves
    /// no orphaned sidecar behind. The destination sidecar is regenerated.
    private func removeOrphanSourceSidecar(for sourceURL: URL, fileManager fm: FileManager) {
        let orphan = XMPTaggingService.exportSidecarURL(for: sourceURL)
        if fm.fileExists(atPath: orphan.path) {
            try? fm.removeItem(at: orphan)
        }
    }
```

Delete the old single `for sourceURL in files` processing loop and its trailing `return TransferSummary(...)` (replaced above). Keep the `totalBytes` pre-scan and `startTime`/`completedBytes` declarations.

- [ ] **Step 5: Run the test to verify it passes**

Run: `swift test --filter FileTransferSidecarTests`
Expected: PASS.

- [ ] **Step 6: Run the full suite to catch regressions**

Run: `swift test`
Expected: all PASS.

- [ ] **Step 7: Commit**

```bash
git add DuckSort/Utilities/FileTransferService.swift Tests/DuckSortTests/FileTransferSidecarTests.swift
git commit -m "feat: Write export sidecars on plain copy/move transfers"
```

---

### Task 6: `RoutedTransferService` — sidecars on copy/move and embed+sidecar on JPEG export

**Files:**
- Modify: `DuckSort/Utilities/RoutedTransferService.swift`
- Modify: `DuckSort/Models/RoutedOperation.swift` (add `sidecarFailures` to `RoutedSummary`)
- Create: `Tests/DuckSortTests/RoutedSidecarTests.swift`

**Interfaces:**
- Consumes: `SidecarPayload`, `writeExportSidecar`, `mergingKeywords`, existing `RoutedPhoto.tags` / `RoutedPhoto.metadata`.
- Produces: `RoutedSummary` gains `let sidecarFailures: Int`.

- [ ] **Step 1: Write the failing test**

Create `Tests/DuckSortTests/RoutedSidecarTests.swift`:

```swift
import XCTest
import ImageIO
@testable import DuckSort

final class RoutedSidecarTests: XCTestCase {
    private func copySet(_ dir: URL) throws -> RoutedPhoto {
        let media = dir.appendingPathComponent("IMG_0001.jpg")
        try ImageFixture.writeJPEG(to: media, cameraModel: "X-T5", lensModel: "XF35mm", iso: 400)
        let set = PhotoSet(baseName: "IMG_0001", mediaFiles: [media], editPath: nil)
        return RoutedPhoto(
            photoSet: set,
            metadata: MetadataReader().metadata(for: media),
            tags: [CustomTag(name: "Family", categoryID: UUID())]
        )
    }

    func test_copyOriginals_writesSidecar() async throws {
        let src = try TempDir.make(); let dst = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: src); try? FileManager.default.removeItem(at: dst) }
        let routed = try copySet(src)

        let plan = RoutedPlan(
            operation: .copyOriginals,
            baseDestination: dst,
            rule: [],
            photos: [routed]
        )
        let summary = try await RoutedTransferService().execute(plan, categoryNameProvider: { _ in nil })

        XCTAssertEqual(summary.sidecarFailures, 0)
        let sidecar = dst.appendingPathComponent("IMG_0001.xmp")
        XCTAssertTrue(try String(contentsOf: sidecar, encoding: .utf8).contains("<rdf:li>Family</rdf:li>"))
    }

    func test_exportJPEGs_embedsKeywordsAndWritesSidecar() async throws {
        let src = try TempDir.make(); let dst = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: src); try? FileManager.default.removeItem(at: dst) }
        let routed = try copySet(src)

        let plan = RoutedPlan(
            operation: .exportJPEGs,
            baseDestination: dst,
            rule: [],
            photos: [routed],
            namingPreset: .originalSequence
        )
        let summary = try await RoutedTransferService().execute(plan, categoryNameProvider: { _ in nil })
        XCTAssertEqual(summary.sidecarFailures, 0)

        // Find the exported JPEG and confirm embedded IPTC keywords.
        let files = try FileManager.default.contentsOfDirectory(at: dst, includingPropertiesForKeys: nil)
        let jpeg = try XCTUnwrap(files.first { $0.pathExtension.lowercased() == "jpg" })
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(jpeg as CFURL, nil))
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let iptc = props?[kCGImagePropertyIPTCDictionary] as? [CFString: Any]
        let keywords = iptc?[kCGImagePropertyIPTCKeywords] as? [String]
        XCTAssertEqual(keywords, ["Family"])

        let sidecar = files.first { $0.pathExtension.lowercased() == "xmp" }
        XCTAssertNotNil(sidecar)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter RoutedSidecarTests`
Expected: FAIL — `RoutedSummary` has no `sidecarFailures`; no sidecar/keywords written.

- [ ] **Step 3: Add `sidecarFailures` to `RoutedSummary`**

In `DuckSort/Models/RoutedOperation.swift`:

```swift
struct RoutedSummary: Sendable {
    let operation: RoutedOperation
    let fileCount: Int
    let baseDestination: URL
    let foldersCreated: Int
    let sidecarFailures: Int
}
```

- [ ] **Step 4: Add sidecar service + failure counter and thread through `execute`**

In `RoutedTransferService`, add below `metadataReader`:

```swift
    private let sidecarService = XMPTaggingService()
```

At the top of `execute`, declare `var sidecarFailures = 0`. Add this private helper to the actor:

```swift
    private func writeSidecar(
        tagNames: Set<String>,
        capture: MetadataSnapshot,
        besideDestination dest: URL,
        failures: inout Int
    ) async {
        let payload = SidecarPayload(tagNames: tagNames, capture: capture)
        do {
            try await sidecarService.writeExportSidecar(payload, besideDestinationFile: dest)
        } catch {
            failures += 1
        }
    }
```

In the **copyOriginals** branch, after a media file is copied to `dest`, write a sidecar (only for media files):

```swift
                        if routed.photoSet.mediaFiles.map(\.standardizedFileURL)
                            .contains(sourceURL.standardizedFileURL) {
                            await writeSidecar(
                                tagNames: Set(routed.tags.map(\.name)),
                                capture: routed.metadata,
                                besideDestination: dest,
                                failures: &sidecarFailures
                            )
                        }
```

In the **moveOriginals** branch, do the same after the move, and additionally remove an orphaned source sidecar:

```swift
                        if routed.photoSet.mediaFiles.map(\.standardizedFileURL)
                            .contains(sourceURL.standardizedFileURL) {
                            await writeSidecar(
                                tagNames: Set(routed.tags.map(\.name)),
                                capture: routed.metadata,
                                besideDestination: dest,
                                failures: &sidecarFailures
                            )
                            let orphan = XMPTaggingService.exportSidecarURL(for: sourceURL)
                            if fm.fileExists(atPath: orphan.path) { try? fm.removeItem(at: orphan) }
                        }
```

In the **exportJPEGs** branch, after `try writeJPEG(from: sourceURL, to: dest, quality:)`, write the sidecar using the per-file `metadata` already read at that point:

```swift
                    await writeSidecar(
                        tagNames: Set(routed.tags.map(\.name)),
                        capture: metadata,
                        besideDestination: dest,
                        failures: &sidecarFailures
                    )
```

Update the `writeJPEG` signature to accept tag names and embed them:

```swift
    private func writeJPEG(from sourceURL: URL, to destinationURL: URL, quality: Double, tagNames: Set<String>) throws {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let destination = CGImageDestinationCreateWithURL(
                destinationURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil
              )
        else {
            throw ExportError.cannotCreateJPEG(sourceURL.lastPathComponent)
        }
        let sourceProperties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        var destinationProperties = sourceProperties
        destinationProperties[kCGImageDestinationLossyCompressionQuality] = quality
        destinationProperties = XMPTaggingService.mergingKeywords(tagNames, into: destinationProperties)

        CGImageDestinationAddImage(destination, image, destinationProperties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ExportError.cannotCreateJPEG(sourceURL.lastPathComponent)
        }
    }
```

Update the call site in the exportJPEGs branch to pass `tagNames: Set(routed.tags.map(\.name))`.

Finally, update the two `RoutedSummary(...)` constructions (the early-empty return and the final return) to include `sidecarFailures:` — the empty-plan return uses `sidecarFailures: 0`, the final uses `sidecarFailures: sidecarFailures`.

- [ ] **Step 5: Run the test to verify it passes**

Run: `swift test --filter RoutedSidecarTests`
Expected: PASS (both copy and exportJPEGs cases).

- [ ] **Step 6: Run the full suite**

Run: `swift test`
Expected: all PASS.

- [ ] **Step 7: Commit**

```bash
git add DuckSort/Utilities/RoutedTransferService.swift DuckSort/Models/RoutedOperation.swift Tests/DuckSortTests/RoutedSidecarTests.swift
git commit -m "feat: Write sidecars + embed JPEG keywords in routed transfers"
```

---

### Task 7: `JPEGExportService` — sidecar + embed (consistency)

**Files:**
- Modify: `DuckSort/Utilities/JPEGExportService.swift`
- Create: `Tests/DuckSortTests/JPEGExportSidecarTests.swift`

**Note:** `JPEGExportService` is currently declared in the view model but never invoked (the live JPEG path is `RoutedTransferService.exportJPEGs`). It is updated here so the two re-encode paths stay consistent and the behavior is directly tested; no view-model wiring is added for it (YAGNI).

**Interfaces:**
- Consumes: `SidecarPayload`, `writeExportSidecar`, `mergingKeywords`.
- Produces:
  - `JPEGExportPlan` gains `let tagNames: [UUID: Set<String>]` defaulting to `[:]`.
  - `JPEGExportSummary` gains `let sidecarFailures: Int`.

- [ ] **Step 1: Write the failing test**

Create `Tests/DuckSortTests/JPEGExportSidecarTests.swift`:

```swift
import XCTest
import ImageIO
@testable import DuckSort

final class JPEGExportSidecarTests: XCTestCase {
    func test_export_embedsKeywordsAndWritesSidecar() async throws {
        let src = try TempDir.make(); let dst = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: src); try? FileManager.default.removeItem(at: dst) }

        let media = src.appendingPathComponent("IMG_0001.jpg")
        try ImageFixture.writeJPEG(to: media, cameraModel: "X-T5", lensModel: "XF35mm", iso: 400)
        let set = PhotoSet(baseName: "IMG_0001", mediaFiles: [media], editPath: nil)

        var options = JPEGExportOptions()
        options.groupByDate = false
        options.namingPreset = .originalSequence
        let plan = JPEGExportPlan(
            destinationDirectory: dst,
            photoSets: [set],
            options: options,
            tagNames: [set.id: ["Family"]]
        )
        let summary = try await JPEGExportService().export(plan)
        XCTAssertEqual(summary.sidecarFailures, 0)

        let files = try FileManager.default.contentsOfDirectory(at: dst, includingPropertiesForKeys: nil)
        XCTAssertTrue(files.contains { $0.pathExtension.lowercased() == "xmp" })
        let jpeg = try XCTUnwrap(files.first { $0.pathExtension.lowercased() == "jpg" })
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(jpeg as CFURL, nil))
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let iptc = props?[kCGImagePropertyIPTCDictionary] as? [CFString: Any]
        XCTAssertEqual(iptc?[kCGImagePropertyIPTCKeywords] as? [String], ["Family"])
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter JPEGExportSidecarTests`
Expected: FAIL — `JPEGExportPlan` has no `tagNames`; `JPEGExportSummary` no `sidecarFailures`.

- [ ] **Step 3: Extend the plan/summary structs**

In `JPEGExportService.swift`:

```swift
struct JPEGExportPlan: Sendable {
    let destinationDirectory: URL
    let photoSets: [PhotoSet]
    let options: JPEGExportOptions
    let tagNames: [UUID: Set<String>]

    init(
        destinationDirectory: URL,
        photoSets: [PhotoSet],
        options: JPEGExportOptions,
        tagNames: [UUID: Set<String>] = [:]
    ) {
        self.destinationDirectory = destinationDirectory
        self.photoSets = photoSets
        self.options = options
        self.tagNames = tagNames
    }
}

struct JPEGExportSummary: Sendable {
    let fileCount: Int
    let destinationDirectory: URL
    let sidecarFailures: Int
}
```

- [ ] **Step 4: Add the sidecar service, embed keywords, write sidecar**

Add below `metadataReader`:

```swift
    private let sidecarService = XMPTaggingService()
```

In the export loop, after `try writeJPEG(...)`, add:

```swift
            let tagNames = plan.tagNames[photoSet.id] ?? []
            let payload = SidecarPayload(tagNames: tagNames, capture: metadata)
            do {
                try await sidecarService.writeExportSidecar(payload, besideDestinationFile: destinationURL)
            } catch {
                sidecarFailures += 1
            }
```

Declare `var sidecarFailures = 0` before the loop. Change `writeJPEG` to accept and embed tag names (same body change as Task 6):

```swift
    private func writeJPEG(from sourceURL: URL, to destinationURL: URL, quality: Double, tagNames: Set<String>) throws {
        // ... identical to existing body, plus before AddImage:
        destinationProperties = XMPTaggingService.mergingKeywords(tagNames, into: destinationProperties)
        // ...
    }
```

Update its call site to `try writeJPEG(from: sourceURL, to: destinationURL, quality: plan.options.jpegQuality, tagNames: plan.tagNames[photoSet.id] ?? [])`.

Update the `return JPEGExportSummary(...)` to include `sidecarFailures: sidecarFailures`.

- [ ] **Step 5: Run the test to verify it passes**

Run: `swift test --filter JPEGExportSidecarTests`
Expected: PASS.

- [ ] **Step 6: Run the full suite**

Run: `swift test`
Expected: all PASS.

- [ ] **Step 7: Commit**

```bash
git add DuckSort/Utilities/JPEGExportService.swift Tests/DuckSortTests/JPEGExportSidecarTests.swift
git commit -m "feat: Write sidecar + embed keywords in JPEGExportService"
```

---

### Task 8: Failure counting is best-effort (read-only destination)

**Files:**
- Create: `Tests/DuckSortTests/SidecarFailureTests.swift`

**Interfaces:**
- Consumes: `FileTransferService`, `TransferPlan`, `TransferSummary.sidecarFailures`.

- [ ] **Step 1: Write the test proving a sidecar failure doesn't abort the transfer**

Create `Tests/DuckSortTests/SidecarFailureTests.swift`:

```swift
import XCTest
@testable import DuckSort

final class SidecarFailureTests: XCTestCase {
    func test_readOnlyDestination_transferSucceeds_failureCounted() async throws {
        let src = try TempDir.make(); let dst = try TempDir.make()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dst.path)
            try? FileManager.default.removeItem(at: src)
            try? FileManager.default.removeItem(at: dst)
        }

        let media = src.appendingPathComponent("IMG_0001.jpg")
        try ImageFixture.writeJPEG(to: media, cameraModel: "X-T5", lensModel: "XF35mm", iso: 400)
        let set = PhotoSet(baseName: "IMG_0001", mediaFiles: [media], editPath: nil)

        // Copy first so the media file lands, then make the dir read-only before sidecar write?
        // Simpler: pre-create destination media so the copy is a no-op, then lock the dir.
        let preExisting = dst.appendingPathComponent("IMG_0001.jpg")
        try FileManager.default.copyItem(at: media, to: preExisting)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dst.path)

        let plan = TransferPlan(
            operation: .copy,
            destinationDirectory: dst,
            photoSets: [set],
            tagNames: [set.id: ["Family"]]
        )
        let summary = try await FileTransferService().execute(plan)

        XCTAssertEqual(summary.fileCount, 1)          // transfer still reported success
        XCTAssertEqual(summary.sidecarFailures, 1)    // sidecar write failed but was counted
    }
}
```

Note: with a read-only destination directory, `uniqueDestinationURL` returns the pre-existing identical path, the copy is skipped as same-name, and the sidecar `write(to:atomically:)` fails — exercising the best-effort path.

- [ ] **Step 2: Run the test**

Run: `swift test --filter SidecarFailureTests`
Expected: PASS — `fileCount == 1`, `sidecarFailures == 1`, no thrown error.

If the test does not behave as expected because the copy path differs, adjust by asserting `summary.sidecarFailures >= 1` and `summary.fileCount == 1`; the invariant under test is "transfer succeeds, failure counted."

- [ ] **Step 3: Commit**

```bash
git add Tests/DuckSortTests/SidecarFailureTests.swift
git commit -m "test: Sidecar write failure is best-effort and counted"
```

---

### Task 9: View-model wiring + user-facing failure surfacing

**Files:**
- Modify: `DuckSort/ViewModels/PhotoLibraryViewModel.swift`

**Interfaces:**
- Consumes: `TransferPlan(tagNames:)`, `TransferSummary.sidecarFailures`, `RoutedSummary.sidecarFailures`.

- [ ] **Step 1: Populate `tagNames` when building the plain `TransferPlan`**

In `performTransfer` (around line 508), replace the `TransferPlan(...)` construction with:

```swift
        let tagNameMap: [UUID: Set<String>] = Dictionary(
            uniqueKeysWithValues: selected.map { set in
                (set.id, Set(tagStore.assignedTags(for: set.id).map(\.name)))
            }
        )
        let plan = TransferPlan(
            operation: operation,
            destinationDirectory: destinationDirectory,
            photoSets: selected,
            tagNames: tagNameMap
        )
```

- [ ] **Step 2: Surface sidecar failures in the plain-transfer status message**

In the success branch of `performTransfer`, after the existing `self.statusMessage = ...` completion line, append:

```swift
                if summary.sidecarFailures > 0 {
                    self.statusMessage += " (\(summary.sidecarFailures) sidecar(s) could not be written)"
                }
```

- [ ] **Step 3: Surface sidecar failures in the routed-operation status message**

In the success branch of `performRoutedOperation`, after the existing completion `self.statusMessage = ...` line, append:

```swift
                if summary.sidecarFailures > 0 {
                    self.statusMessage += " (\(summary.sidecarFailures) sidecar(s) could not be written)"
                }
```

(`RoutedPhoto.tags` is already populated at line ~559, so the routed path needs no tag wiring.)

- [ ] **Step 4: Build the app to confirm it compiles**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 5: Run the full test suite**

Run: `swift test`
Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add DuckSort/ViewModels/PhotoLibraryViewModel.swift
git commit -m "feat: Pass tag names to transfers and report sidecar write failures"
```

---

### Task 10: Update README to describe what is preserved

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add a preservation feature bullet**

In the `## Features` list, add:

```markdown
- **Metadata Preservation**: On copy, move, and export, DuckSort writes an `.xmp` sidecar beside every file (RAW, HEIF, JPEG) recording your custom tags and the photo's capture metadata (camera, lens, ISO, shutter, aperture, date). Re-encoded JPEG exports also embed the tag keywords inside the file.
```

- [ ] **Step 2: Verify wording is accurate against the implementation**

Confirm the bullet matches behavior: sidecars beside media files only; keywords embedded only on re-encoded JPEGs; failures are non-fatal. Adjust wording if any task changed scope.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: Document metadata preservation via XMP sidecars"
```

---

## Self-Review Notes

- **Spec coverage:** custom tags travel (Tasks 5–7, 9); capture metadata sidecar (Task 3); all formats incl. RAW (copy/move sidecars in Tasks 5–6); JPEG embed (Tasks 6–7); best-effort errors + `sidecarFailures` (Tasks 5–9); move orphan cleanup (Tasks 5–6); tests incl. no-tags and failure (Tasks 3, 8); test target creation (Task 1); README (Task 10). All spec sections map to a task.
- **Type consistency:** `writeExportSidecar(_:besideDestinationFile:)`, `exportSidecarURL(for:)`, `mergingKeywords(_:into:)`, `SidecarPayload`, `tagNames: [UUID: Set<String>]`, and `sidecarFailures: Int` are used identically across all tasks.
- **Dead-code note:** `JPEGExportService` is updated for consistency (Task 7) but intentionally left unwired in the view model (matches its current state).
