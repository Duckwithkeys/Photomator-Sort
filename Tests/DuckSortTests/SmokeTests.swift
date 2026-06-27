import XCTest
@testable import DuckSort

final class SmokeTests: XCTestCase {
    func test_metadataSnapshot_defaultsAreNil() {
        let snapshot = MetadataSnapshot()
        XCTAssertNil(snapshot.cameraModel)
        XCTAssertNil(snapshot.captureDate)
    }

    func test_photoFilterRule_matchesCorrectly() {
        let setWithEdit = PhotoSet(id: UUID(), baseName: "photo1", mediaFiles: [URL(fileURLWithPath: "photo1.jpg")], editPath: URL(fileURLWithPath: "photo1.photo-edit"))
        let setWithoutEdit = PhotoSet(id: UUID(), baseName: "photo2", mediaFiles: [URL(fileURLWithPath: "photo2.jpg")], editPath: nil)
        
        XCTAssertTrue(PhotoFilterRule.allPhotos.matches(setWithEdit))
        XCTAssertTrue(PhotoFilterRule.allPhotos.matches(setWithoutEdit))
        
        XCTAssertTrue(PhotoFilterRule.editedOnly.matches(setWithEdit))
        XCTAssertFalse(PhotoFilterRule.editedOnly.matches(setWithoutEdit))
        
        XCTAssertFalse(PhotoFilterRule.uneditedOnly.matches(setWithEdit))
        XCTAssertTrue(PhotoFilterRule.uneditedOnly.matches(setWithoutEdit))
    }
}
