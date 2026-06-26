//
//  FileTransferService.swift
//  PhotomatorSort
//
//  Performs copy and move operations off the main actor. Future export modules
//  can decorate `TransferPlan` with metadata-derived subfolders or naming rules.

import Foundation

enum TransferOperation: String, CaseIterable, Identifiable, Sendable {
    case copy = "Copy"
    case move = "Move"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .copy: return "doc.on.doc"
        case .move: return "folder"
        }
    }

    var progressTitle: String {
        switch self {
        case .copy: return "Copying"
        case .move: return "Moving"
        }
    }
}

struct TransferPlan: Sendable {
    let operation: TransferOperation
    let destinationDirectory: URL
    let photoSets: [PhotoSet]
    let tagNames: [UUID: Set<String>]
    /// Pre-read EXIF metadata for every photo set. The transfer service
    /// previously re-read this via `MetadataReader.metadata(for:)` for
    /// each transfer, duplicating the work `loadMetadataAndTags` already
    /// did at scan time. Keys are photo set IDs.
    let metadata: [UUID: MetadataSnapshot]

    init(
        operation: TransferOperation,
        destinationDirectory: URL,
        photoSets: [PhotoSet],
        tagNames: [UUID: Set<String>] = [:],
        metadata: [UUID: MetadataSnapshot] = [:]
    ) {
        self.operation = operation
        self.destinationDirectory = destinationDirectory
        self.photoSets = photoSets
        self.tagNames = tagNames
        self.metadata = metadata
    }

    var files: [URL] {
        photoSets.flatMap(\.allFiles)
    }
}

struct TransferSummary: Sendable {
    let operation: TransferOperation
    let fileCount: Int
    let destinationDirectory: URL
    let sidecarFailures: Int
}

actor FileTransferService {
    private let sidecarService = XMPTaggingService()

    struct TransferJob: Sendable {
        let photoSet: PhotoSet
        let sourceURL: URL
        let tagNames: Set<String>
        let setMetadata: MetadataSnapshot
        let mediaSet: Set<URL>
        let precomputedSize: Int64
    }

    func execute(
        _ plan: TransferPlan,
        progress: (@Sendable (FileOperationProgress) async -> Void)? = nil
    ) async throws -> TransferSummary {
        let fm = FileManager.default

        guard fm.isDirectory(atPath: plan.destinationDirectory.path) else {
            throw TransferError.destinationUnavailable(plan.destinationDirectory.path)
        }

        var transferred = 0
        let files = plan.files

        // Chunked parallel size computation — one stat() syscall per file
        // is cheap, but spawning 1,500 tasks to do 1,500 trivial syscalls
        // burns more time in task scheduling than in actual I/O.
        let fileSizes = await Self.chunkedFileSizes(for: files)

        let totalBytes = fileSizes.values.reduce(Int64(0), +)
        let startTime = Date()
        var completedBytes: Int64 = 0
        var sidecarFailures = 0

        var jobs: [TransferJob] = []
        jobs.reserveCapacity(files.count)
        for photoSet in plan.photoSets {
            let mediaSet = Set(photoSet.mediaFiles.map { $0.standardizedFileURL })
            let tagNames = plan.tagNames[photoSet.id] ?? []
            let setMetadata = plan.metadata[photoSet.id] ?? MetadataSnapshot()

            for sourceURL in photoSet.allFiles {
                jobs.append(TransferJob(
                    photoSet: photoSet,
                    sourceURL: sourceURL,
                    tagNames: tagNames,
                    setMetadata: setMetadata,
                    mediaSet: mediaSet,
                    precomputedSize: fileSizes[sourceURL] ?? 0
                ))
            }
        }

        let limit = min(8, ProcessInfo.processInfo.activeProcessorCount)
        let localSidecarService = self.sidecarService

        try await withThrowingTaskGroup(of: (Int64, Bool, URL).self) { group in
            var index = 0
            var runningTasks = 0
            while index < jobs.count && runningTasks < limit {
                let job = jobs[index]
                index += 1
                runningTasks += 1
                group.addTask {
                    try await self.executeJob(job, plan: plan, sidecarService: localSidecarService)
                }
            }

            while let (fileSize, sidecarFailed, sourceURL) = try await group.next() {
                runningTasks -= 1
                transferred += 1
                completedBytes += fileSize
                if sidecarFailed {
                    sidecarFailures += 1
                }

                let elapsed = Date().timeIntervalSince(startTime)
                let bps = elapsed > 0 ? Double(completedBytes) / elapsed : 0
                await progress?(FileOperationProgress(
                    completed: transferred,
                    total: files.count,
                    currentName: sourceURL.lastPathComponent,
                    completedBytes: completedBytes,
                    totalBytes: totalBytes,
                    bytesPerSecond: bps
                ))

                if index < jobs.count {
                    let job = jobs[index]
                    index += 1
                    runningTasks += 1
                    group.addTask {
                        try await self.executeJob(job, plan: plan, sidecarService: localSidecarService)
                    }
                }
            }
        }

        return TransferSummary(
            operation: plan.operation,
            fileCount: transferred,
            destinationDirectory: plan.destinationDirectory,
            sidecarFailures: sidecarFailures
        )
    }

    nonisolated private func executeJob(
        _ job: TransferJob,
        plan: TransferPlan,
        sidecarService: XMPTaggingService
    ) async throws -> (Int64, Bool, URL) {
        let fm = FileManager.default
        let destinationURL = FileNaming.uniqueDestinationURL(
            for: job.sourceURL, in: plan.destinationDirectory, fileManager: fm
        )
        // Reuse the size from the pre-pass; only stat the file if the
        // pre-pass missed it (shouldn't happen in normal flows).
        var fileSize = job.precomputedSize
        if fileSize == 0 {
            fileSize = (try? fm.attributesOfItem(atPath: job.sourceURL.path)[.size] as? Int64) ?? 0
        }
        let isSameLocation = job.sourceURL.standardizedFileURL == destinationURL.standardizedFileURL

        if !isSameLocation {
            switch plan.operation {
            case .copy: try fm.copyItem(at: job.sourceURL, to: destinationURL)
            case .move: try fm.moveItem(at: job.sourceURL, to: destinationURL)
            }
        }

        var sidecarFailed = false
        if job.mediaSet.contains(job.sourceURL.standardizedFileURL) {
            let payload = SidecarPayload(
                tagNames: job.tagNames,
                capture: job.setMetadata,
                iptc: XMPTaggingService.iptcFromPreferences()
            )
            let sourceSidecarURL = XMPTaggingService.exportSidecarURL(for: job.sourceURL)
            do {
                try sidecarService.writeExportSidecar(
                    payload,
                    besideDestinationFile: destinationURL,
                    mergingSourceSidecar: sourceSidecarURL
                )
            } catch {
                sidecarFailed = true
            }

            if plan.operation == .move && !isSameLocation {
                removeOrphanSourceSidecar(for: job.sourceURL, fileManager: fm)
            }
        }

        return (fileSize, sidecarFailed, job.sourceURL)
    }

    /// On move, delete any pre-existing source `.xmp` so the moved file leaves
    /// no orphaned sidecar behind. The destination sidecar is regenerated.
    nonisolated private func removeOrphanSourceSidecar(for sourceURL: URL, fileManager fm: FileManager) {
        let orphan = XMPTaggingService.exportSidecarURL(for: sourceURL)
        if fm.fileExists(atPath: orphan.path) {
            try? fm.removeItem(at: orphan)
        }
    }

    /// Chunked stat() across every URL. Returns a `[URL: Int64]` map so the
    /// transfer jobs can carry precomputed sizes and `executeJob` doesn't
    /// need to stat files a second time for progress reporting.
    private static func chunkedFileSizes(for files: [URL]) async -> [URL: Int64] {
        guard !files.isEmpty else { return [:] }
        let cores = max(1, ProcessInfo.processInfo.activeProcessorCount)
        let chunkSize = max(50, files.count / cores)

        return await withTaskGroup(of: [(URL, Int64)].self) { group in
            for chunkStart in stride(from: 0, to: files.count, by: chunkSize) {
                let upper = min(chunkStart + chunkSize, files.count)
                let slice = Array(files[chunkStart..<upper])
                group.addTask {
                    let fm = FileManager.default
                    var out: [(URL, Int64)] = []
                    out.reserveCapacity(slice.count)
                    for url in slice {
                        let size = (try? fm.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
                        out.append((url, size))
                    }
                    return out
                }
            }
            var map: [URL: Int64] = [:]
            map.reserveCapacity(files.count)
            for await partial in group {
                for (url, size) in partial {
                    map[url] = size
                }
            }
            return map
        }
    }
}

enum TransferError: LocalizedError {
    case destinationUnavailable(String)
    case noSelection
    case sameSourceAndDestination

    var errorDescription: String? {
        switch self {
        case .destinationUnavailable(let path):
            return "The destination folder is not available: \(path)"
        case .noSelection:
            return "Select at least one photo set before transferring."
        case .sameSourceAndDestination:
            return "Choose a different destination folder before moving files."
        }
    }
}
