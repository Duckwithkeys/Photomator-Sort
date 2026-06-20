//
//  ExportOptions.swift
//  PhotomatorSort
//

import Foundation

enum ExportNamingPreset: String, CaseIterable, Identifiable, Sendable {
    case originalSequence = "Original + Sequence"
    case dateOriginalSequence = "Date + Original + Sequence"
    case cameraOriginalSequence = "Camera + Original + Sequence"

    var id: String { rawValue }

    var tokens: [NamingToken] {
        switch self {
        case .originalSequence:
            return [.originalName, .sequence]
        case .dateOriginalSequence:
            return [.captureDate, .originalName, .sequence]
        case .cameraOriginalSequence:
            return [.cameraModel, .originalName, .sequence]
        }
    }
}

enum NamingToken: Sendable {
    case originalName
    case captureDate
    case sequence
    case cameraModel
    case lensModel
}

struct JPEGExportOptions: Sendable {
    var namingPreset: ExportNamingPreset = .dateOriginalSequence
    var groupByDate = true
    var groupByCamera = false
    var groupByLens = false
    var jpegQuality: Double = 0.92
}

struct MetadataSnapshot: Sendable {
    var cameraModel: String?
    var lensModel: String?
    var captureDate: Date?
    var aperture: Double?
    var shutterSpeed: Double?
    var iso: Int?
}

struct FileOperationProgress: Sendable {
    let completed: Int
    let total: Int
    let currentName: String
    
    // Bytes tracking
    let completedBytes: Int64
    let totalBytes: Int64
    let bytesPerSecond: Double

    var displayText: String {
        "\(completed)/\(total): \(currentName)"
    }
}

