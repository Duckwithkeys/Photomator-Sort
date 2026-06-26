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
    case rawSony     = "arw"
    case rawCanon2   = "cr2"
    case rawCanon3   = "cr3"
    case rawNikon    = "nef"
    case rawAdobe    = "dng"
    case rawOlympus  = "orf"
    case rawPanasonic = "rw2"
    case rawPentax   = "pef"
    
    case hif         = "hif"
    case heic        = "heic"
    case heif        = "heif"
    
    case jpeg        = "jpg"
    case jpegExtended = "jpeg"
    
    case photoEdit   = "photo-edit"

    static let imageExtensions: Set<FileExtension> = [
        .rawFuji, .rawGeneric, .rawSony, .rawCanon2, .rawCanon3, .rawNikon, .rawAdobe, .rawOlympus, .rawPanasonic, .rawPentax,
        .hif, .heic, .heif, .jpeg, .jpegExtended
    ]

    static let rawLikeExtensions: Set<String> = [
        "heic", "heif", "hif", "raf", "arw", "cr2", "cr3", "nef", "dng", "orf", "rw2", "pef"
    ]

    /// Extensions that should be treated as HEIF-family image containers.
    /// Used to pick the right decode path (NSImage native vs. ImageIO
    /// embedded thumbnail).
    static let heifLikeExtensions: Set<String> = ["heic", "heif", "hif"]
}

// MARK: - Scanner

/// O(1) extension → enum case dictionary. Replaces the old two-step lookup
/// (`Set.contains` + `FileExtension(rawValue:)` which internally scans every
/// case). Built once at type-init.
private let extensionLookup: [String: FileExtension] = {
    var d: [String: FileExtension] = [:]
    d.reserveCapacity(FileExtension.allCases.count)
    for ext in FileExtension.allCases {
        d[ext.rawValue] = ext
    }
    return d
}()

struct FileScanner: Sendable {

    struct ScanResult: Sendable {
        let sourceDirectories: [URL]
        let photoSets: [PhotoSet]
        let scannedFileCount: Int
        let ignoredFileCount: Int
        let failedDirectories: [URL]

        init(
            sourceDirectories: [URL],
            photoSets: [PhotoSet],
            scannedFileCount: Int,
            ignoredFileCount: Int,
            failedDirectories: [URL] = []
        ) {
            self.sourceDirectories = sourceDirectories
            self.photoSets = photoSets
            self.scannedFileCount = scannedFileCount
            self.ignoredFileCount = ignoredFileCount
            self.failedDirectories = failedDirectories
        }
    }

    /// Scan a directory recursively, suitable for choosing an SD card root.
    func scanDirectory(_ url: URL, jpegOnly: Bool = false) async throws -> ScanResult {
        try await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            guard fm.isReadableFile(atPath: url.path),
                  fm.isDirectory(atPath: url.path)
            else {
                throw ScanError.notADirectory(url.path)
            }

            let keys: Set<URLResourceKey> = [
                .isDirectoryKey, .isPackageKey, .isRegularFileKey,
                .fileSizeKey, .contentModificationDateKey
            ]
            guard let enumerator = fm.enumerator(
                at: url,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                throw ScanError.notADirectory(url.path)
            }

            var mediaURLsByBaseName: [String: [URL]] = [:]
            var sidecars: [String: URL] = [:]
            var ignoredFileCount = 0

            while let itemURL = enumerator.nextObject() as? URL {
                try Task.checkCancellation()

                let ext = itemURL.pathExtension.lowercased()
                guard let extensionKind = extensionLookup[ext] else {
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

            let photoSets = Self.assemble(media: mediaURLsByBaseName, sidecars: sidecars)
            let total = photoSets.reduce(0) { $0 + $1.allFiles.count }

            return ScanResult(
                sourceDirectories: [url],
                photoSets: photoSets,
                scannedFileCount: total,
                ignoredFileCount: ignoredFileCount
            )
        }.value
    }

    /// Group a flat list of individual files (e.g. dropped or imported via the
    /// open panel) into PhotoSets using the same base-name + sidecar logic as a
    /// recursive directory scan.
    func scanFiles(_ urls: [URL], jpegOnly: Bool = false) async -> ScanResult {
        await Task.detached(priority: .userInitiated) {
            let keys: Set<URLResourceKey> = [.isDirectoryKey, .isPackageKey, .isRegularFileKey]

            var mediaURLsByBaseName: [String: [URL]] = [:]
            var sidecars: [String: URL] = [:]
            var ignoredFileCount = 0
            var failedFiles: [URL] = []

            for itemURL in urls {
                do {
                    try Task.checkCancellation()

                    let ext = itemURL.pathExtension.lowercased()
                    guard let extensionKind = extensionLookup[ext] else {
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
                    } else {
                        ignoredFileCount += 1
                    }
                } catch {
                    failedFiles.append(itemURL)
                }
            }

            let photoSets = Self.assemble(media: mediaURLsByBaseName, sidecars: sidecars)
            let total = photoSets.reduce(0) { $0 + $1.allFiles.count }

            return ScanResult(
                sourceDirectories: [],
                photoSets: photoSets,
                scannedFileCount: total,
                ignoredFileCount: ignoredFileCount,
                failedDirectories: failedFiles
            )
        }.value
    }

    /// Build sorted PhotoSets by merging sidecars into matching base names.
    private static func assemble(media: [String: [URL]], sidecars: [String: URL]) -> [PhotoSet] {
        var photoSets: [PhotoSet] = []
        var processed: Set<String> = []

        for (groupingKey, mediaURLs) in media {
            processed.insert(groupingKey)
            photoSets.append(PhotoSet(
                baseName: displayBaseName(for: groupingKey),
                mediaFiles: mediaURLs,
                editPath: sidecars[groupingKey]
            ))
        }

        // Handle sidecar-only entries (rare edge case).
        for (groupingKey, path) in sidecars where !processed.contains(groupingKey) {
            photoSets.append(PhotoSet(
                baseName: displayBaseName(for: groupingKey),
                mediaFiles: [],
                editPath: path
            ))
        }

        // Sorting moved to the ViewModel (scanSourceDirectories) so the data
        // crosses the actor boundary in a single order instead of being
        // sorted three times across the pipeline.

        return photoSets
    }

    /// Scan multiple directories recursively and concurrently, combining the results.
    func scanDirectories(_ urls: [URL], jpegOnly: Bool = false) async -> ScanResult {
        if urls.isEmpty {
            return ScanResult(sourceDirectories: [], photoSets: [], scannedFileCount: 0, ignoredFileCount: 0, failedDirectories: [])
        }

        return await withTaskGroup(of: ScanResult.self) { group in
            for url in urls {
                group.addTask {
                    do {
                        return try await self.scanDirectory(url, jpegOnly: jpegOnly)
                    } catch {
                        return ScanResult(
                            sourceDirectories: [url],
                            photoSets: [],
                            scannedFileCount: 0,
                            ignoredFileCount: 0,
                            failedDirectories: [url]
                        )
                    }
                }
            }

            var allPhotoSets: [PhotoSet] = []
            var totalScanned = 0
            var totalIgnored = 0
            var failedDirs: [URL] = []

            for await result in group {
                allPhotoSets.append(contentsOf: result.photoSets)
                totalScanned += result.scannedFileCount
                totalIgnored += result.ignoredFileCount
                failedDirs.append(contentsOf: result.failedDirectories)
            }

            // Sorting moved to the ViewModel (scanSourceDirectories) so the
            // data crosses the actor boundary in a single order instead of
            // being sorted three times across the pipeline.

            return ScanResult(
                sourceDirectories: urls,
                photoSets: allPhotoSets,
                scannedFileCount: totalScanned,
                ignoredFileCount: totalIgnored,
                failedDirectories: failedDirs
            )
        }
    }

    private static func groupingKey(for url: URL) -> String {
        url.deletingPathExtension().standardizedFileURL.path
    }

    private static func displayBaseName(for groupingKey: String) -> String {
        if let slash = groupingKey.lastIndex(of: "/") {
            return String(groupingKey[groupingKey.index(after: slash)...])
        }
        return groupingKey
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
