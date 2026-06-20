//
//  FileScanner.swift
//  PhotomatorSort
//
//  Background scanner that discovers media files under a source directory and
//  groups them by shared base name within the same containing folder.
//

import Foundation

/// Recognized file extensions for photoshoot sorting.
enum FileExtension: String, CaseIterable, Sendable {
    case rawFuji     = "raf"
    case rawGeneric  = "raw"
    case heif        = "hif"
    case jpeg        = "jpg"
    case jpegExtended = "jpeg"
    case photoEdit   = "photo-edit"

    static let imageExtensions: Set<FileExtension> = [
        .rawFuji, .rawGeneric, .heif, .jpeg, .jpegExtended
    ]
}

// MARK: - Scanner

actor FileScanner {

    struct ScanResult: Sendable {
        let sourceDirectories: [URL]
        let photoSets: [PhotoSet]
        let scannedFileCount: Int
        let ignoredFileCount: Int

        init(
            sourceDirectories: [URL],
            photoSets: [PhotoSet],
            scannedFileCount: Int,
            ignoredFileCount: Int
        ) {
            self.sourceDirectories = sourceDirectories
            self.photoSets = photoSets
            self.scannedFileCount = scannedFileCount
            self.ignoredFileCount = ignoredFileCount
        }
    }

    /// Scan a directory recursively, suitable for choosing an SD card root.
    func scanDirectory(_ url: URL, jpegOnly: Bool = false) async throws -> ScanResult {
        let fm = FileManager.default
        guard fm.isReadableFile(atPath: url.path),
              fm.isDirectory(atPath: url.path)
        else {
            throw ScanError.notADirectory(url.path)
        }

        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isPackageKey, .isRegularFileKey]
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else {
            throw ScanError.notADirectory(url.path)
        }

        // Group by folder + base name so duplicate camera filenames in different
        // shoots do not collapse into one asset.
        var mediaURLsByBaseName: [String: [URL]] = [:]
        var sidecars: [String: URL] = [:]
        var ignoredFileCount = 0

        while let itemURL = enumerator.nextObject() as? URL {
            try Task.checkCancellation()

            guard let extensionKind = FileExtension(rawValue: itemURL.pathExtension.lowercased()) else {
                if itemURL.hasDirectoryPath {
                    continue
                }

                ignoredFileCount += 1
                continue
            }

            let values = try itemURL.resourceValues(forKeys: keys)
            let baseName = itemURL.deletingPathExtension().lastPathComponent
            let groupingKey = Self.groupingKey(for: itemURL)

            if FileExtension.imageExtensions.contains(extensionKind),
               values.isRegularFile == true,
               !baseName.isEmpty {
                if jpegOnly && extensionKind != .jpeg && extensionKind != .jpegExtended {
                    ignoredFileCount += 1
                    continue
                }
                mediaURLsByBaseName[groupingKey, default: []].append(itemURL)
            } else if extensionKind == .photoEdit,
                      (values.isRegularFile == true || values.isDirectory == true || values.isPackage == true),
                      !baseName.isEmpty {
                if jpegOnly {
                    ignoredFileCount += 1
                    continue
                }
                sidecars[groupingKey] = itemURL

                if values.isDirectory == true || values.isPackage == true {
                    enumerator.skipDescendants()
                }
            } else {
                ignoredFileCount += 1
            }
        }

        // Build PhotoSets by merging sidecars into matching base names.
        var photoSets: [PhotoSet] = []
        var processed: Set<String> = []

        for (groupingKey, mediaURLs) in mediaURLsByBaseName {
            processed.insert(groupingKey)
            let editPath = sidecars[groupingKey]
            photoSets.append(PhotoSet(
                baseName: Self.displayBaseName(for: groupingKey),
                mediaFiles: mediaURLs,
                editPath: editPath
            ))
        }

        // Handle sidecar-only entries (rare edge case).
        for (groupingKey, path) in sidecars where !processed.contains(groupingKey) {
            photoSets.append(PhotoSet(
                baseName: Self.displayBaseName(for: groupingKey),
                mediaFiles: [],
                editPath: path
            ))
        }

        photoSets.sort {
            $0.baseName.localizedStandardCompare($1.baseName) == .orderedAscending
        }

        let total = photoSets.reduce(0) { $0 + $1.allFiles.count }

        return ScanResult(
            sourceDirectories: [url],
            photoSets: photoSets,
            scannedFileCount: total,
            ignoredFileCount: ignoredFileCount
        )
    }

    /// Scan multiple directories recursively and concurrently, combining the results.
    func scanDirectories(_ urls: [URL], jpegOnly: Bool = false) async throws -> ScanResult {
        if urls.isEmpty {
            return ScanResult(sourceDirectories: [], photoSets: [], scannedFileCount: 0, ignoredFileCount: 0)
        }

        return try await withThrowingTaskGroup(of: ScanResult.self) { group in
            for url in urls {
                group.addTask {
                    try await self.scanDirectory(url, jpegOnly: jpegOnly)
                }
            }

            var allPhotoSets: [PhotoSet] = []
            var totalScanned = 0
            var totalIgnored = 0

            while let result = try await group.next() {
                allPhotoSets.append(contentsOf: result.photoSets)
                totalScanned += result.scannedFileCount
                totalIgnored += result.ignoredFileCount
            }

            allPhotoSets.sort {
                $0.baseName.localizedStandardCompare($1.baseName) == .orderedAscending
            }

            return ScanResult(
                sourceDirectories: urls,
                photoSets: allPhotoSets,
                scannedFileCount: totalScanned,
                ignoredFileCount: totalIgnored
            )
        }
    }

    private static func groupingKey(for url: URL) -> String {
        url.deletingPathExtension().standardizedFileURL.path
    }

    private static func displayBaseName(for groupingKey: String) -> String {
        URL(fileURLWithPath: groupingKey).lastPathComponent
    }
}

// MARK: - Errors

enum ScanError: LocalizedError {
    case notADirectory(String)

    var errorDescription: String? {
        switch self {
        case .notADirectory(let path):
            return "The selected path is not a valid directory: \(path)"
        }
    }
}
