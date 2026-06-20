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
