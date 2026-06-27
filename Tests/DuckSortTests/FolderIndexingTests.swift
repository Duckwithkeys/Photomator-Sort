//
//  FolderIndexingTests.swift
//  DuckSortTests
//

import XCTest
@testable import DuckSort

@MainActor
final class FolderIndexingTests: XCTestCase {

    func testHierarchicalFolderIndexing() {
        let viewModel = PhotoLibraryViewModel()

        let parentURL = URL(fileURLWithPath: "/Users/oliver/Photos")
        let childURL = parentURL.appendingPathComponent("2026")
        let grandchildURL = childURL.appendingPathComponent("Vacation")

        let set1 = PhotoSet(
            baseName: "photo1",
            mediaFiles: [parentURL.appendingPathComponent("photo1.jpg")],
            editPath: nil
        )
        let set2 = PhotoSet(
            baseName: "photo2",
            mediaFiles: [childURL.appendingPathComponent("photo2.jpg")],
            editPath: nil
        )
        let set3 = PhotoSet(
            baseName: "photo3",
            mediaFiles: [grandchildURL.appendingPathComponent("photo3.jpg")],
            editPath: nil
        )

        // Setting photoSets triggers global count update and derived state updates,
        // which builds the folder tree index.
        viewModel.photoSets = [set1, set2, set3]

        // 1. Verify parent-child subfolder tree logic
        let parentChildren = viewModel.childSubfolders(of: parentURL)
        XCTAssertEqual(parentChildren.count, 1)
        XCTAssertEqual(parentChildren.first?.standardizedFileURL.path, childURL.standardizedFileURL.path)

        let childChildren = viewModel.childSubfolders(of: childURL)
        XCTAssertEqual(childChildren.count, 1)
        XCTAssertEqual(childChildren.first?.standardizedFileURL.path, grandchildURL.standardizedFileURL.path)

        let grandchildChildren = viewModel.childSubfolders(of: grandchildURL)
        XCTAssertTrue(grandchildChildren.isEmpty)

        // 2. Verify recursive photo counts
        XCTAssertEqual(viewModel.recursivePhotoCount(in: parentURL), 3)
        XCTAssertEqual(viewModel.recursivePhotoCount(in: childURL), 2)
        XCTAssertEqual(viewModel.recursivePhotoCount(in: grandchildURL), 1)
    }
}
