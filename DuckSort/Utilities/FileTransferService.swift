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

    init(
        operation: TransferOperation,
        destinationDirectory: URL,
        photoSets: [PhotoSet],
        tagNames: [UUID: Set<String>] = [:]
    ) {
        self.operation = operation
        self.destinationDirectory = destinationDirectory
        self.photoSets = photoSets
        self.tagNames = tagNames
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
    private let metadataReader = MetadataReader()

    struct TransferJob: Sendable {
        let photoSet: PhotoSet
        let sourceURL: URL
        let tagNames: Set<String>
        let setMetadata: MetadataSnapshot
        let mediaSet: Set<URL>
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

        let totalBytes = await withTaskGroup(of: Int64.self) { group in
            for sourceURL in files {
                group.addTask {
                    let fm = FileManager.default
                    let attrs = try? fm.attributesOfItem(atPath: sourceURL.path)
                    return attrs?[.size] as? Int64 ?? 0
                }
            }
            var sum: Int64 = 0
            for await size in group {
                sum += size
            }
            return sum
        }
        
        let startTime = Date()
        var completedBytes: Int64 = 0
        var sidecarFailures = 0

        var jobs: [TransferJob] = []
        for photoSet in plan.photoSets {
            let mediaSet = Set(photoSet.mediaFiles.map { $0.standardizedFileURL })
            let tagNames = plan.tagNames[photoSet.id] ?? []
            let setMetadata = photoSet.preferredPreviewURL
                .map { metadataReader.metadata(for: $0) } ?? MetadataSnapshot()

            for sourceURL in photoSet.allFiles {
                jobs.append(TransferJob(
                    photoSet: photoSet,
                    sourceURL: sourceURL,
                    tagNames: tagNames,
                    setMetadata: setMetadata,
                    mediaSet: mediaSet
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
        let destinationURL = uniqueDestinationURL(
            for: job.sourceURL, in: plan.destinationDirectory, fileManager: fm
        )
        let fileSize = (try? fm.attributesOfItem(atPath: job.sourceURL.path)[.size] as? Int64) ?? 0
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
                capture: job.setMetadata
            )
            let sourceSidecarURL = XMPTaggingService.exportSidecarURL(for: job.sourceURL)
            do {
                try await sidecarService.writeExportSidecar(
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
            let candidateName: String
            if ext.isEmpty {
                candidateName = "\(base)-\(index)"
            } else {
                candidateName = "\(base)-\(index).\(ext)"
            }

            let candidate = directory.appendingPathComponent(candidateName)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        return original
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
