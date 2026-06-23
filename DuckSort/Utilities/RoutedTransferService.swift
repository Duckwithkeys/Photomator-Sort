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
    private let sidecarService = XMPTaggingService()

    struct RoutedJob: Sendable {
        let sourceURL: URL
        let destinationFolder: URL
        let photoSet: PhotoSet
        let tagNames: Set<String>
        let metadata: MetadataSnapshot
        let mediaSet: Set<URL>
    }

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
                foldersCreated: 0,
                sidecarFailures: 0
            )
        }

        var totalFiles = 0
        var foldersCreated = 0
        var sidecarFailures = 0

        // 1. Pre-walk & compute multipliers
        struct FileWalkItem: Sendable {
            let url: URL
            let multiplier: Int
        }
        var walkItems: [FileWalkItem] = []
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
                walkItems.append(FileWalkItem(url: fileURL, multiplier: multiplier))
            }
        }

        // 2. Parallel size computation
        let totalBytes = await withTaskGroup(of: Int64.self) { group in
            for item in walkItems {
                group.addTask {
                    let fm = FileManager.default
                    let size = (try? fm.attributesOfItem(atPath: item.url.path)[.size] as? Int64) ?? 0
                    return size * Int64(item.multiplier)
                }
            }
            var sum: Int64 = 0
            for await size in group {
                sum += size
            }
            return sum
        }

        // 3. Pre-create directories sequentially to avoid race conditions
        for routed in plan.photos {
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
        }

        // 4. Build job list
        var jobs: [RoutedJob] = []
        for routed in plan.photos {
            let folders = ExportPathRouter.destinationFolders(
                base: plan.baseDestination,
                rule: plan.rule,
                metadata: routed.metadata,
                assignedTags: routed.tags,
                categoryNameProvider: categoryNameProvider
            )
            let mediaSet = Set(routed.photoSet.mediaFiles.map { $0.standardizedFileURL })
            let tagNames = Set(routed.tags.map(\.name))

            for folder in folders {
                for sourceURL in routed.photoSet.allFiles {
                    jobs.append(RoutedJob(
                        sourceURL: sourceURL,
                        destinationFolder: folder,
                        photoSet: routed.photoSet,
                        tagNames: tagNames,
                        metadata: routed.metadata,
                        mediaSet: mediaSet
                    ))
                }
            }
        }

        // 5. Execute jobs in bounded concurrent task group
        let limit = min(8, ProcessInfo.processInfo.activeProcessorCount)
        let localSidecarService = self.sidecarService
        let startTime = Date()
        var completedBytes: Int64 = 0
        var processed = 0

        try await withThrowingTaskGroup(of: (Int64, Bool, URL, URL).self) { group in
            var index = 0
            var runningTasks = 0
            while index < jobs.count && runningTasks < limit {
                let job = jobs[index]
                index += 1
                runningTasks += 1
                group.addTask {
                    try await self.executeJob(job, operation: plan.operation, sidecarService: localSidecarService)
                }
            }

            while let (fileSize, sidecarFailed, _, dest) = try await group.next() {
                runningTasks -= 1
                processed += 1
                completedBytes += fileSize
                if sidecarFailed {
                    sidecarFailures += 1
                }

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

                if index < jobs.count {
                    let job = jobs[index]
                    index += 1
                    runningTasks += 1
                    group.addTask {
                        try await self.executeJob(job, operation: plan.operation, sidecarService: localSidecarService)
                    }
                }
            }
        }

        // 6. Clean up original source files for moveOriginals
        if plan.operation == .moveOriginals {
            for routed in plan.photos {
                let mediaSet = Set(routed.photoSet.mediaFiles.map { $0.standardizedFileURL })
                for sourceURL in routed.photoSet.allFiles {
                    if fm.fileExists(atPath: sourceURL.path) {
                        try? fm.removeItem(at: sourceURL)
                    }
                    if mediaSet.contains(sourceURL.standardizedFileURL) {
                        let orphan = XMPTaggingService.exportSidecarURL(for: sourceURL)
                        if fm.fileExists(atPath: orphan.path) {
                            try? fm.removeItem(at: orphan)
                        }
                    }
                }
            }
        }

        return RoutedSummary(
            operation: plan.operation,
            fileCount: processed,
            baseDestination: plan.baseDestination,
            foldersCreated: foldersCreated,
            sidecarFailures: sidecarFailures
        )
    }

    // MARK: - Sidecar writing

    nonisolated private func executeJob(
        _ job: RoutedJob,
        operation: RoutedOperation,
        sidecarService: XMPTaggingService
    ) async throws -> (Int64, Bool, URL, URL) {
        let fm = FileManager.default
        let dest = uniqueDestinationURL(
            for: job.sourceURL, in: job.destinationFolder, fileManager: fm
        )
        let fileSize = (try? fm.attributesOfItem(atPath: job.sourceURL.path)[.size] as? Int64) ?? 0
        let isSameLocation = job.sourceURL.standardizedFileURL == dest.standardizedFileURL

        if !isSameLocation {
            try fm.copyItem(at: job.sourceURL, to: dest)
        }

        var sidecarFailed = false
        if job.mediaSet.contains(job.sourceURL.standardizedFileURL) {
            let sourceSidecar = XMPTaggingService.exportSidecarURL(for: job.sourceURL)
            let payload = SidecarPayload(tagNames: job.tagNames, capture: job.metadata)
            do {
                try await sidecarService.writeExportSidecar(
                    payload,
                    besideDestinationFile: dest,
                    mergingSourceSidecar: sourceSidecar
                )
            } catch {
                sidecarFailed = true
            }
        }

        return (fileSize, sidecarFailed, job.sourceURL, dest)
    }

    // MARK: - JPEG writing

    private func writeJPEG(from sourceURL: URL, to destinationURL: URL, quality: Double, tagNames: Set<String>) throws {
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
        destinationProperties = XMPTaggingService.mergingKeywords(tagNames, into: destinationProperties)

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

    nonisolated private func uniqueDestinationURL(
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

    nonisolated private func uniqueDestinationURL(
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
