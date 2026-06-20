//
//  JPEGExportService.swift
//  PhotomatorSort
//

import Foundation
import ImageIO
import UniformTypeIdentifiers

struct JPEGExportPlan: Sendable {
    let destinationDirectory: URL
    let photoSets: [PhotoSet]
    let options: JPEGExportOptions
}

struct JPEGExportSummary: Sendable {
    let fileCount: Int
    let destinationDirectory: URL
}

actor JPEGExportService {
    private let metadataReader = MetadataReader()

    func export(
        _ plan: JPEGExportPlan,
        progress: (@Sendable (FileOperationProgress) async -> Void)? = nil
    ) async throws -> JPEGExportSummary {
        let fm = FileManager.default

        guard fm.isDirectory(atPath: plan.destinationDirectory.path) else {
            throw TransferError.destinationUnavailable(plan.destinationDirectory.path)
        }

        let exportableSets = plan.photoSets.filter { $0.preferredPreviewURL != nil }
        var exported = 0
        
        var totalBytes: Int64 = 0
        for set in exportableSets {
            if let preview = set.preferredPreviewURL {
                let size = (try? fm.attributesOfItem(atPath: preview.path)[.size] as? Int64) ?? 0
                totalBytes += size
            }
        }
        
        let startTime = Date()
        var completedBytes: Int64 = 0

        for (index, photoSet) in exportableSets.enumerated() {
            try Task.checkCancellation()
            guard let sourceURL = photoSet.preferredPreviewURL else { continue }

            let metadata = metadataReader.metadata(for: sourceURL)
            let folderURL = try destinationFolder(
                base: plan.destinationDirectory,
                metadata: metadata,
                options: plan.options,
                fileManager: fm
            )
            let fileName = exportFileName(
                photoSet: photoSet,
                metadata: metadata,
                sequence: index + 1,
                options: plan.options
            )
            let destinationURL = uniqueDestinationURL(
                forFileName: fileName,
                in: folderURL,
                fileManager: fm
            )

            try writeJPEG(from: sourceURL, to: destinationURL, quality: plan.options.jpegQuality)
            exported += 1
            
            let fileSize = (try? fm.attributesOfItem(atPath: sourceURL.path)[.size] as? Int64) ?? 0
            completedBytes += fileSize
            let elapsed = Date().timeIntervalSince(startTime)
            let bps = elapsed > 0 ? Double(completedBytes) / elapsed : 0

            await progress?(FileOperationProgress(
                completed: exported,
                total: exportableSets.count,
                currentName: destinationURL.lastPathComponent,
                completedBytes: completedBytes,
                totalBytes: totalBytes,
                bytesPerSecond: bps
            ))
        }

        return JPEGExportSummary(fileCount: exported, destinationDirectory: plan.destinationDirectory)
    }

    private func destinationFolder(
        base: URL,
        metadata: MetadataSnapshot,
        options: JPEGExportOptions,
        fileManager: FileManager
    ) throws -> URL {
        var folder = base

        if options.groupByDate {
            folder.appendPathComponent(Self.dateFolderName(for: metadata.captureDate))
        }

        if options.groupByCamera {
            folder.appendPathComponent(FilenameSanitizer.clean(metadata.cameraModel ?? "", fallback: "Unknown Camera"))
        }

        if options.groupByLens {
            folder.appendPathComponent(FilenameSanitizer.clean(metadata.lensModel ?? "", fallback: "Unknown Lens"))
        }

        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func exportFileName(
        photoSet: PhotoSet,
        metadata: MetadataSnapshot,
        sequence: Int,
        options: JPEGExportOptions
    ) -> String {
        let parts = options.namingPreset.tokens.map { token in
            switch token {
            case .originalName:
                return photoSet.baseName
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

    private static func dateFolderName(for date: Date?) -> String {
        guard let date else { return "Unknown Date" }
        return folderDateFormatter.string(from: date)
    }

    private static func dateFileName(for date: Date?) -> String {
        guard let date else { return "Unknown-Date" }
        return fileDateFormatter.string(from: date)
    }

    private static let folderDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let fileDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"
        return formatter
    }()
}

enum ExportError: LocalizedError {
    case cannotCreateJPEG(String)

    var errorDescription: String? {
        switch self {
        case .cannotCreateJPEG(let name):
            return "Could not create a JPEG export for \(name)."
        }
    }
}

