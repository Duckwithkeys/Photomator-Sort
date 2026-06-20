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

    var files: [URL] {
        photoSets.flatMap(\.allFiles)
    }
}

struct TransferSummary: Sendable {
    let operation: TransferOperation
    let fileCount: Int
    let destinationDirectory: URL
}

actor FileTransferService {
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

        var totalBytes: Int64 = 0
        for sourceURL in files {
            do {
                let attrs = try fm.attributesOfItem(atPath: sourceURL.path)
                totalBytes += attrs[.size] as? Int64 ?? 0
            } catch {}
        }
        
        let startTime = Date()
        var completedBytes: Int64 = 0

        for sourceURL in files {
            try Task.checkCancellation()

            let destinationURL = uniqueDestinationURL(
                for: sourceURL,
                in: plan.destinationDirectory,
                fileManager: fm
            )

            let fileSize = (try? fm.attributesOfItem(atPath: sourceURL.path)[.size] as? Int64) ?? 0

            if sourceURL.standardizedFileURL == destinationURL.standardizedFileURL {
                transferred += 1
                completedBytes += fileSize
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
                continue
            }

            switch plan.operation {
            case .copy:
                try fm.copyItem(at: sourceURL, to: destinationURL)
            case .move:
                try fm.moveItem(at: sourceURL, to: destinationURL)
            }

            transferred += 1
            completedBytes += fileSize
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
        }

        return TransferSummary(
            operation: plan.operation,
            fileCount: transferred,
            destinationDirectory: plan.destinationDirectory
        )
    }

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
