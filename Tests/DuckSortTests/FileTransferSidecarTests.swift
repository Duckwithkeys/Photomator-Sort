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

    func test_copy_rawJpegShareSidecar_capturesReadableJpegMetadata() async throws {
        let src = try TempDir.make(); let dst = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: src); try? FileManager.default.removeItem(at: dst) }

        // Readable JPEG with EXIF + an unreadable RAW sibling sharing the basename.
        let jpg = src.appendingPathComponent("IMG.jpg")
        try ImageFixture.writeJPEG(to: jpg, cameraModel: "X-T5", lensModel: "XF35mm", iso: 400)
        let raf = src.appendingPathComponent("IMG.raf")
        try Data("not a real raw".utf8).write(to: raf)
        let set = PhotoSet(baseName: "IMG", mediaFiles: [jpg, raf], editPath: nil)

        let plan = TransferPlan(
            operation: .copy,
            destinationDirectory: dst,
            photoSets: [set],
            tagNames: [set.id: ["Family"]]
        )
        let summary = try await FileTransferService().execute(plan)
        XCTAssertEqual(summary.sidecarFailures, 0)

        // The single shared sidecar must carry the JPEG-derived camera model,
        // not empty data from the unreadable RAF processed last.
        let xml = try String(contentsOf: dst.appendingPathComponent("IMG.xmp"), encoding: .utf8)
        XCTAssertTrue(xml.contains("tiff:Model=\"X-T5\""), "shared sidecar should keep readable JPEG metadata")
        XCTAssertTrue(xml.contains("<rdf:li>Family</rdf:li>"))
    }

    func test_move_sameLocation_preservesSidecar() async throws {
        let dir = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: dir) }
        let media = dir.appendingPathComponent("IMG_0009.jpg")
        try ImageFixture.writeJPEG(to: media, cameraModel: "X-T5", lensModel: "XF35mm", iso: 400)
        let set = PhotoSet(baseName: "IMG_0009", mediaFiles: [media], editPath: nil)

        // destination == source directory => same-location move, file not relocated
        let plan = TransferPlan(
            operation: .move,
            destinationDirectory: dir,
            photoSets: [set],
            tagNames: [set.id: ["Family"]]
        )
        let summary = try await FileTransferService().execute(plan)
        XCTAssertEqual(summary.sidecarFailures, 0)
        let sidecar = dir.appendingPathComponent("IMG_0009.xmp")
        XCTAssertTrue(FileManager.default.fileExists(atPath: sidecar.path),
                      "Same-location move must not delete the freshly written sidecar")
    }

    func test_copy_preservesRatingAndCameraMetadata() async throws {
        let src = try TempDir.make()
        let dst = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: src); try? FileManager.default.removeItem(at: dst) }

        let media = src.appendingPathComponent("IMG_0002.jpg")
        try ImageFixture.writeJPEG(to: media, cameraModel: "X-T5", lensModel: "XF35mm", iso: 400)
        
        let sidecarURL = src.appendingPathComponent("IMG_0002.xmp")
        let initialXMP = """
        <x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="XMP Core 6.0.0">
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description rdf:about=""
                xmlns:xmp="http://ns.adobe.com/xap/1.0/"
                xmp:Rating="3">
            </rdf:Description>
          </rdf:RDF>
        </x:xmpmeta>
        """
        try initialXMP.write(to: sidecarURL, atomically: true, encoding: .utf8)
        
        let set = PhotoSet(baseName: "IMG_0002", mediaFiles: [media], editPath: nil)

        let plan = TransferPlan(
            operation: .copy,
            destinationDirectory: dst,
            photoSets: [set],
            tagNames: [set.id: ["Family"]]
        )
        let summary = try await FileTransferService().execute(plan)

        XCTAssertEqual(summary.sidecarFailures, 0)
        let destSidecar = dst.appendingPathComponent("IMG_0002.xmp")
        XCTAssertTrue(FileManager.default.fileExists(atPath: destSidecar.path))
        
        let xml = try String(contentsOf: destSidecar, encoding: .utf8)
        XCTAssertTrue(xml.contains("xmp:Rating=\"3\""), "Destination sidecar should preserve the source rating when it is not in media metadata")
        XCTAssertTrue(xml.contains("<rdf:li>Family</rdf:li>"), "Destination sidecar should contain custom tag keywords")
        XCTAssertTrue(xml.contains("tiff:Model=\"X-T5\""), "Destination sidecar should preserve camera model")
    }
}
