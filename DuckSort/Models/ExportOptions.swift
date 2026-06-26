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

    // Advanced EXIF fields
    var focalLength: Double?
    var focalLengthIn35mm: Double?
    var whiteBalance: String?
    var flashFired: Bool?
    var flashMode: String?
    var pixelWidth: Int?
    var pixelHeight: Int?
    var orientation: Int?
    var colorSpace: String?
    var colorProfile: String?
    var gpsLatitude: Double?
    var gpsLongitude: Double?
    var gpsAltitude: Double?
    var exposureProgram: String?
    var meteringMode: String?
    var exposureBias: Double?
    var caption: String?
}

/// Photographer / copyright / contact metadata that gets embedded into
/// every export sidecar when the user has opted in via Settings → Copyright.
/// All fields are optional — only the ones the user has filled in are
/// written to the XMP packet.
struct IPTCMetadata: Sendable, Equatable {
    var creatorName: String?
    var copyrightNotice: String?
    var contactEmail: String?
    var contactPhone: String?
    var contactWebsite: String?
    var rightsUsageTerms: String?
}

/// Everything an export sidecar records for one destination file:
/// the custom tag keywords, the capture metadata snapshot, and any
/// IPTC/copyright fields the user has configured.
struct SidecarPayload: Sendable {
    let tagNames: Set<String>
    let capture: MetadataSnapshot
    let iptc: IPTCMetadata
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

