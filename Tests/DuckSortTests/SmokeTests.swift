import XCTest
@testable import DuckSort

final class SmokeTests: XCTestCase {
    func test_metadataSnapshot_defaultsAreNil() {
        let snapshot = MetadataSnapshot()
        XCTAssertNil(snapshot.cameraModel)
        XCTAssertNil(snapshot.captureDate)
    }
}
