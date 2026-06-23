//
//  ExportOptions.swift
//  PhotomatorSort
//

import Foundation



struct MetadataSnapshot: Sendable {
    var cameraModel: String?
    var lensModel: String?
    var captureDate: Date?
    var aperture: Double?
    var shutterSpeed: Double?
    var iso: Int?
    var rating: Int?
    var pick: Int?
}

/// Everything an export sidecar records for one destination file:
/// the custom tag keywords plus the capture metadata snapshot.
struct SidecarPayload: Sendable {
    let tagNames: Set<String>
    let capture: MetadataSnapshot
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

