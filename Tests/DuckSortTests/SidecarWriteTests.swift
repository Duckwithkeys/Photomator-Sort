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
            ),
            iptc: IPTCMetadata()
        )

        let service = XMPTaggingService()
        try service.writeExportSidecar(payload, besideDestinationFile: media)

        let sidecar = dir.appendingPathComponent("IMG_0001.xmp")
        let xml = try String(contentsOf: sidecar, encoding: .utf8)
        XCTAssertTrue(xml.contains("<rdf:li>Ceremony</rdf:li>"))
        XCTAssertTrue(xml.contains("<rdf:li>Family</rdf:li>"))
        XCTAssertTrue(xml.contains("tiff:Model=\"X-T5\""))
        XCTAssertTrue(xml.contains("exif:LensModel=\"XF35mm\""))
        XCTAssertTrue(xml.contains("exif:ISOSpeedRatings=\"400\""))
    }

    func test_writeExportSidecar_escapesQuoteInAttributeValue() async throws {
        let dir = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: dir) }
        let media = dir.appendingPathComponent("IMG_0002.RAF")
        let payload = SidecarPayload(
            tagNames: [],
            capture: MetadataSnapshot(cameraModel: "Cam \"Pro\"", lensModel: nil,
                                      captureDate: nil, aperture: nil, shutterSpeed: nil, iso: nil),
            iptc: IPTCMetadata()
        )
        try XMPTaggingService().writeExportSidecar(payload, besideDestinationFile: media)
        let xml = try String(contentsOf: dir.appendingPathComponent("IMG_0002.xmp"), encoding: .utf8)
        XCTAssertTrue(xml.contains("tiff:Model=\"Cam &quot;Pro&quot;\""))
        XCTAssertFalse(xml.contains("\"Pro\""))
    }

    func test_writeExportSidecar_mergesIntoExistingSidecar() async throws {
        let dir = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: dir) }
        
        let sourceSidecar = dir.appendingPathComponent("IMG_0003.xmp")
        
        let initialXMP = """
        <x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="XMP Core 6.0.0">
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description rdf:about=""
                xmlns:xmp="http://ns.adobe.com/xap/1.0/"
                xmlns:dc="http://purl.org/dc/elements/1.1/"
                xmlns:customNs="http://example.com/custom/"
                xmp:Rating="4"
                customNs:CustomProp="KeepMe">
              <dc:subject>
                <rdf:Bag>
                  <rdf:li>InitialTag</rdf:li>
                </rdf:Bag>
              </dc:subject>
            </rdf:Description>
          </rdf:RDF>
        </x:xmpmeta>
        """
        try initialXMP.write(to: sourceSidecar, atomically: true, encoding: .utf8)
        
        let destMedia = dir.appendingPathComponent("IMG_0003_dest.RAF")
        let payload = SidecarPayload(
            tagNames: ["NewTag"],
            capture: MetadataSnapshot(
                cameraModel: "X-T5", lensModel: "XF35mm",
                captureDate: nil, aperture: 2.8, shutterSpeed: 0.004, iso: 400, rating: 5
            ),
            iptc: IPTCMetadata()
        )
        
        let service = XMPTaggingService()
        try service.writeExportSidecar(payload, besideDestinationFile: destMedia, mergingSourceSidecar: sourceSidecar)
        
        let destSidecar = dir.appendingPathComponent("IMG_0003_dest.xmp")
        let mergedXML = try String(contentsOf: destSidecar, encoding: .utf8)
        
        XCTAssertTrue(mergedXML.contains("customNs:CustomProp=\"KeepMe\""), "Should preserve custom namespace attributes")
        XCTAssertTrue(mergedXML.contains("xmp:Rating=\"5\""), "Should update rating to payload value")
        XCTAssertTrue(mergedXML.contains("tiff:Model=\"X-T5\""))
        XCTAssertTrue(mergedXML.contains("exif:LensModel=\"XF35mm\""))
        XCTAssertTrue(mergedXML.contains("<rdf:li>NewTag</rdf:li>"))
    }
}
