//
//  RoutedTransferService.swift
//  PhotomatorSort
//
//  Executes copy and move using the same export routing rule.
//  For each photo in the plan it computes a destination folder via
//  ExportPathRouter, then performs the requested operation.
//

import Foundation

actor RoutedTransferService {

    private let sidecarService = XMPTaggingService()

    struct RoutedJob: Sendable {
        let sourceURL: URL
        let destinationFolder: URL
        let photoSet: PhotoSet
        let tagNames: Set<String>
        let metadata: MetadataSnapshot
        let mediaSet: Set<URL>
    }

    /// Per-file item produced by the routing pass. Used to drive both the
    /// size pre-pass and the progress multiplier calculation. Declared at
    /// type scope so the static `chunkedTotalBytes` helper can read it.
    struct FileWalkItem: Sendable {
        let url: URL
        let multiplier: Int
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

        // 0. Compute `destinationFolders` ONCE per photo. Used by phases
        //    1, 3, and 4 below — computing it three times was the dominant
        //    overhead on large routed transfers.
        struct RoutingResult: Sendable {
            let routed: RoutedPhoto
            let folders: [URL]
        }
        let routingResults: [RoutingResult] = plan.photos.map { routed in
            let folders = ExportPathRouter.destinationFolders(
                base: plan.baseDestination,
                rule: plan.rule,
                metadata: routed.metadata,
                assignedTags: routed.tags,
                categoryNameProvider: categoryNameProvider
            )
            return RoutingResult(routed: routed, folders: folders)
        }

        // 1. Pre-walk & compute multipliers
        var walkItems: [FileWalkItem] = []
        walkItems.reserveCapacity(routingResults.reduce(0) { $0 + $1.folders.count * $1.routed.photoSet.allFiles.count })
        for result in routingResults {
            let multiplier = result.folders.count
            for fileURL in result.routed.photoSet.allFiles {
                totalFiles += multiplier
                walkItems.append(FileWalkItem(url: fileURL, multiplier: multiplier))
            }
        }

        // 2. Chunked parallel size computation. Avoids the 1-task-per-file
        //    overhead for very large transfers (1,500+ files) by grouping
        //    stat() syscalls into chunks sized to activeProcessorCount.
        let totalBytes = await Self.chunkedTotalBytes(items: walkItems)

        // 3. Pre-create directories sequentially to avoid race conditions
        for result in routingResults {
            for folder in result.folders {
                let existed = fm.fileExists(atPath: folder.path)
                try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                if !existed { foldersCreated += 1 }
            }
        }

        // 4. Build job list
        var jobs: [RoutedJob] = []
        jobs.reserveCapacity(routingResults.reduce(0) { $0 + $1.folders.count * $1.routed.photoSet.allFiles.count })
        for result in routingResults {
            let routed = result.routed
            let mediaSet = Set(routed.photoSet.mediaFiles.map { $0.standardizedFileURL })
            let tagNames = Set(routed.tags.map(\.name))

            for folder in result.folders {
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
            let payload = SidecarPayload(
                tagNames: job.tagNames,
                capture: job.metadata,
                iptc: XMPTaggingService.iptcFromPreferences()
            )
            do {
                try sidecarService.writeExportSidecar(
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



    // MARK: - Chunked file size computation

    /// Compute total bytes across every file in `items`, applying each
    /// item's multiplier. Groups stat() syscalls into chunks sized to
    /// the active CPU count so 1,500 files don't spawn 1,500 task objects
    /// for trivial work. Multiplier-aware so routed plans (one source →
    /// many destinations) count correctly.
    private static func chunkedTotalBytes(
        items: [FileWalkItem]
    ) async -> Int64 {
        guard !items.isEmpty else { return 0 }
        let cores = max(1, ProcessInfo.processInfo.activeProcessorCount)
        let chunkSize = max(50, items.count / cores)

        return await withTaskGroup(of: Int64.self) { group in
            for chunkStart in stride(from: 0, to: items.count, by: chunkSize) {
                let upper = min(chunkStart + chunkSize, items.count)
                let slice = Array(items[chunkStart..<upper])
                group.addTask {
                    let fm = FileManager.default
                    var sum: Int64 = 0
                    for item in slice {
                        let size = (try? fm.attributesOfItem(atPath: item.url.path)[.size] as? Int64) ?? 0
                        sum += size * Int64(item.multiplier)
                    }
                    return sum
                }
            }
            var total: Int64 = 0
            for await partial in group { total += partial }
            return total
        }
    }

    // MARK: - Unique destination helper

    nonisolated private func uniqueDestinationURL(
        for sourceURL: URL,
        in directory: URL,
        fileManager: FileManager
    ) -> URL {
        FileNaming.uniqueDestinationURL(
            for: sourceURL, in: directory, fileManager: fileManager
        )
    }


}
