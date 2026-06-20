//
//  FileScannerTests.swift
//  DuckSortTests
//
//  Covers FileScanner.scanFiles — the loose-file grouping used by drag-and-drop
//  and the Import command.
//

import XCTest
@testable import DuckSort

final class FileScannerTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DuckSortTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    }

    @discardableResult
    private func makeFile(_ name: String) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try Data().write(to: url)
        return url
    }

    private func set(named base: String, in result: FileScanner.ScanResult) -> PhotoSet? {
        result.photoSets.first { $0.baseName == base }
    }

    func testGroupsByBaseNameAndMergesSidecar() async throws {
        let urls = [
            try makeFile("IMG_001.jpg"),
            try makeFile("IMG_001.raf"),
            try makeFile("IMG_001.photo-edit"),
            try makeFile("IMG_002.jpg")
        ]

        let result = try await FileScanner().scanFiles(urls)

        XCTAssertEqual(result.photoSets.count, 2)

        let first = try XCTUnwrap(set(named: "IMG_001", in: result))
        XCTAssertEqual(first.mediaCount, 2)
        XCTAssertTrue(first.hasEdit)

        let second = try XCTUnwrap(set(named: "IMG_002", in: result))
        XCTAssertEqual(second.mediaCount, 1)
        XCTAssertFalse(second.hasEdit)

        // 2 media + 1 edit for IMG_001, 1 media for IMG_002.
        XCTAssertEqual(result.scannedFileCount, 4)
    }

    func testJpegOnlyIgnoresRawAndSidecars() async throws {
        let urls = [
            try makeFile("IMG_001.jpg"),
            try makeFile("IMG_001.raf"),
            try makeFile("IMG_001.photo-edit"),
            try makeFile("IMG_002.jpg")
        ]

        let result = try await FileScanner().scanFiles(urls, jpegOnly: true)

        XCTAssertEqual(result.photoSets.count, 2)
        let first = try XCTUnwrap(set(named: "IMG_001", in: result))
        XCTAssertEqual(first.mediaCount, 1)
        XCTAssertFalse(first.hasEdit)
        XCTAssertEqual(result.scannedFileCount, 2)
        XCTAssertEqual(result.ignoredFileCount, 2) // .raf + .photo-edit
    }

    func testUnknownExtensionsAreIgnored() async throws {
        let urls = [
            try makeFile("IMG_001.jpg"),
            try makeFile("notes.txt")
        ]

        let result = try await FileScanner().scanFiles(urls)

        XCTAssertEqual(result.photoSets.count, 1)
        XCTAssertEqual(result.ignoredFileCount, 1)
    }
}
