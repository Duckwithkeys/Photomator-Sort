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

        // Pre-copy the media into dst so the destination file already exists.
        // Then make dst read-only so the sidecar write fails.
        // Because uniqueDestinationURL detects same-location when source == destination path,
        // we point the PhotoSet at the already-copied file and use dst as the destination dir.
        // This way the copy is skipped but the sidecar write still fails on read-only dir.
        let preExisting = dst.appendingPathComponent("IMG_0001.jpg")
        try FileManager.default.copyItem(at: media, to: preExisting)

        // Build the set pointing at the file already in dst, then use dst as destination.
        // uniqueDestinationURL detects same location, skips copy, attempts sidecar write.
        let dstMedia = dst.appendingPathComponent("IMG_0001.jpg")
        let dstSet = PhotoSet(baseName: "IMG_0001", mediaFiles: [dstMedia], editPath: nil)

        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dst.path)

        let plan = TransferPlan(
            operation: .copy,
            destinationDirectory: dst,
            photoSets: [dstSet],
            tagNames: [dstSet.id: ["Family"]]
        )
        let summary = try await FileTransferService().execute(plan)

        XCTAssertEqual(summary.fileCount, 1)          // transfer still reported success
        XCTAssertGreaterThanOrEqual(summary.sidecarFailures, 1)    // sidecar write failed but was counted
    }
}
