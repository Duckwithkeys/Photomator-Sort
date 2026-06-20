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
}
