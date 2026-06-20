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
