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
