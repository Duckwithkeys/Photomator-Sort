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
