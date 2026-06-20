//
//  RoutedTransferService.swift
//  PhotomatorSort
//
//  Executes copy, move, and JPEG export using the same export routing rule.
//  For each photo in the plan it computes a destination folder via
//  ExportPathRouter, then performs the requested operation.
//

import Foundation
import ImageIO
import UniformTypeIdentifiers

actor RoutedTransferService {

    private let metadataReader = MetadataReader()

    func execute(
        _ plan: RoutedPlan,
        categoryNameProvider: @Sendable (UUID) -> String?,
        progress: (@Sendable (FileOperationProgress) async -> Void)? = nil
    ) async throws -> RoutedSummary {
        let fm = FileManager.default
        guard fm.isDirectory(atPath: plan.baseDestination.path) else {
            throw TransferError.destinationUnavailable(plan.baseDestination.path)
        }
        if plan.photos.isEmpty {
            return RoutedSummary(
                operation: plan.operation,
                fileCount: 0,
                baseDestination: plan.baseDestination,
                foldersCreated: 0
            )
        }

        var totalFiles = 0
        var totalBytes: Int64 = 0
        var processed = 0
        var foldersCreated = 0

        switch plan.operation {
        case .copyOriginals, .moveOriginals:
            for routed in plan.photos {
                let folders = ExportPathRouter.destinationFolders(
                    base: plan.baseDestination,
                    rule: plan.rule,
                    metadata: routed.metadata,
                    assignedTags: routed.tags,
                    categoryNameProvider: categoryNameProvider
                )
                let multiplier = folders.count
                for fileURL in routed.photoSet.allFiles {
                    totalFiles += multiplier
                    let size = (try? fm.attributesOfItem(atPath: fileURL.path)[.size] as? Int64) ?? 0
                    totalBytes += size * Int64(multiplier)
                }
            }
        case .exportJPEGs:
            for routed in plan.photos {
                guard let previewURL = routed.photoSet.preferredPreviewURL else { continue }
                let folders = ExportPathRouter.destinationFolders(
                    base: plan.baseDestination,
                    rule: plan.rule,
                    metadata: routed.metadata,
                    assignedTags: routed.tags,
                    categoryNameProvider: categoryNameProvider
                )
                totalFiles += folders.count
                let size = (try? fm.attributesOfItem(atPath: previewURL.path)[.size] as? Int64) ?? 0
                totalBytes += size * Int64(folders.count)
            }
        }

        let startTime = Date()
        var completedBytes: Int64 = 0
        var photoSequence = 0
        for routed in plan.photos {
            try Task.checkCancellation()
            let folders = ExportPathRouter.destinationFolders(
                base: plan.baseDestination,
                rule: plan.rule,
                metadata: routed.metadata,
                assignedTags: routed.tags,
                categoryNameProvider: categoryNameProvider
            )
            
            for folder in folders {
                let existed = fm.fileExists(atPath: folder.path)
                try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                if !existed { foldersCreated += 1 }
            }

            photoSequence += 1

            switch plan.operation {
            case .copyOriginals:
                for folder in folders {
                    for sourceURL in routed.photoSet.allFiles {
                        try Task.checkCancellation()
                        let dest = uniqueDestinationURL(
                            for: sourceURL, in: folder, fileManager: fm
                        )
                        let fileSize = (try? fm.attributesOfItem(atPath: sourceURL.path)[.size] as? Int64) ?? 0
                        
                        if sourceURL.standardizedFileURL == dest.standardizedFileURL {
                            processed += 1
                            completedBytes += fileSize
                            let elapsed = Date().timeIntervalSince(startTime)
                            let bps = elapsed > 0 ? Double(completedBytes) / elapsed : 0
                            await progress?(FileOperationProgress(
                                completed: processed,
                                total: totalFiles,
                                currentName: dest.lastPathComponent,
                                completedBytes: completedBytes,
                                totalBytes: totalBytes,
                                bytesPerSecond: bps
                            ))
                            continue
                        }
                        try fm.copyItem(at: sourceURL, to: dest)
                        processed += 1
                        completedBytes += fileSize
                        let elapsed = Date().timeIntervalSince(startTime)
                        let bps = elapsed > 0 ? Double(completedBytes) / elapsed : 0
                        await progress?(FileOperationProgress(
                            completed: processed,
                            total: totalFiles,
                            currentName: dest.lastPathComponent,
                            completedBytes: completedBytes,
                            totalBytes: totalBytes,
                            bytesPerSecond: bps
                        ))
                    }
                }
            case .moveOriginals:
                // For moveOriginals with potential multiple destination folders:
                // Copy to each folder first, and then delete the original source files.
                for folder in folders {
                    for sourceURL in routed.photoSet.allFiles {
                        try Task.checkCancellation()
                        let dest = uniqueDestinationURL(
                            for: sourceURL, in: folder, fileManager: fm
                        )
                        let fileSize = (try? fm.attributesOfItem(atPath: sourceURL.path)[.size] as? Int64) ?? 0
                        
                        if sourceURL.standardizedFileURL == dest.standardizedFileURL {
                            processed += 1
                            completedBytes += fileSize
                            let elapsed = Date().timeIntervalSince(startTime)
                            let bps = elapsed > 0 ? Double(completedBytes) / elapsed : 0
                            await progress?(FileOperationProgress(
                                completed: processed,
                                total: totalFiles,
                                currentName: dest.lastPathComponent,
                                completedBytes: completedBytes,
                                totalBytes: totalBytes,
                                bytesPerSecond: bps
                            ))
                            continue
                        }
                        try fm.copyItem(at: sourceURL, to: dest)
                        processed += 1
                        completedBytes += fileSize
                        let elapsed = Date().timeIntervalSince(startTime)
                        let bps = elapsed > 0 ? Double(completedBytes) / elapsed : 0
                        await progress?(FileOperationProgress(
                            completed: processed,
                            total: totalFiles,
                            currentName: dest.lastPathComponent,
                            completedBytes: completedBytes,
                            totalBytes: totalBytes,
                            bytesPerSecond: bps
                        ))
                    }
                }
                
                // Now clean up original source files since they have been copied to all destinations
                for sourceURL in routed.photoSet.allFiles {
                    if fm.fileExists(atPath: sourceURL.path) {
                        try? fm.removeItem(at: sourceURL)
                    }
                }
                
            case .exportJPEGs:
                guard let sourceURL = routed.photoSet.preferredPreviewURL else { continue }
                let metadata = metadataReader.metadata(for: sourceURL)
                
                for folder in folders {
                    try Task.checkCancellation()
                    let fileName = exportFileName(
                        base: routed.photoSet.baseName,
                        metadata: metadata,
                        sequence: photoSequence,
                        preset: plan.namingPreset
                    )
                    let dest = uniqueDestinationURL(
                        forFileName: fileName, in: folder, fileManager: fm
                    )
                    try writeJPEG(from: sourceURL, to: dest, quality: plan.jpegQuality)
                    
                    let fileSize = (try? fm.attributesOfItem(atPath: sourceURL.path)[.size] as? Int64) ?? 0
                    processed += 1
                    completedBytes += fileSize
                    let elapsed = Date().timeIntervalSince(startTime)
                    let bps = elapsed > 0 ? Double(completedBytes) / elapsed : 0
                    
                    await progress?(FileOperationProgress(
                        completed: processed,
                        total: totalFiles,
                        currentName: dest.lastPathComponent,
                        completedBytes: completedBytes,
                        totalBytes: totalBytes,
                        bytesPerSecond: bps
                    ))
                }
            }
        }

        return RoutedSummary(
            operation: plan.operation,
            fileCount: processed,
            baseDestination: plan.baseDestination,
            foldersCreated: foldersCreated
        )
    }

    // MARK: - JPEG writing

    private func writeJPEG(from sourceURL: URL, to destinationURL: URL, quality: Double) throws {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let destination = CGImageDestinationCreateWithURL(
                destinationURL as CFURL,
                UTType.jpeg.identifier as CFString,
                1,
                nil
              )
        else {
            throw ExportError.cannotCreateJPEG(sourceURL.lastPathComponent)
        }
        let sourceProperties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        var destinationProperties = sourceProperties
        destinationProperties[kCGImageDestinationLossyCompressionQuality] = quality

        CGImageDestinationAddImage(destination, image, destinationProperties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ExportError.cannotCreateJPEG(sourceURL.lastPathComponent)
        }
    }

    private func exportFileName(
        base: String,
        metadata: MetadataSnapshot,
        sequence: Int,
        preset: ExportNamingPreset
    ) -> String {
        let parts = preset.tokens.map { token in
            switch token {
            case .originalName:
                return base
            case .captureDate:
                return Self.dateFileName(for: metadata.captureDate)
            case .sequence:
                return String(format: "%04d", sequence)
            case .cameraModel:
                return FilenameSanitizer.clean(metadata.cameraModel ?? "", fallback: "Unknown Camera")
            case .lensModel:
                return FilenameSanitizer.clean(metadata.lensModel ?? "", fallback: "Unknown Lens")
            }
        }
        return FilenameSanitizer.clean(parts.joined(separator: "_")) + ".jpg"
    }

    private static func dateFileName(for date: Date?) -> String {
        guard let date else { return "Unknown-Date" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: date)
    }

    // MARK: - Unique destination helper

    private func uniqueDestinationURL(
        for sourceURL: URL,
        in directory: URL,
        fileManager: FileManager
    ) -> URL {
        let original = directory.appendingPathComponent(sourceURL.lastPathComponent)
        if sourceURL.standardizedFileURL == original.standardizedFileURL {
            return original
        }
        guard fileManager.fileExists(atPath: original.path) else { return original }
        let base = sourceURL.deletingPathExtension().lastPathComponent
        let ext = sourceURL.pathExtension
        for index in 1...Int.max {
            let candidateName = ext.isEmpty
                ? "\(base)-\(index)"
                : "\(base)-\(index).\(ext)"
            let candidate = directory.appendingPathComponent(candidateName)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return original
    }

    private func uniqueDestinationURL(
        forFileName fileName: String,
        in directory: URL,
        fileManager: FileManager
    ) -> URL {
        let original = directory.appendingPathComponent(fileName)
        guard fileManager.fileExists(atPath: original.path) else { return original }
        let base = original.deletingPathExtension().lastPathComponent
        let ext = original.pathExtension
        for index in 1...Int.max {
            let candidate = directory.appendingPathComponent("\(base)-\(index).\(ext)")
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return original
    }
}
