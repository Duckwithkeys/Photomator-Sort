//
//  PhotoSet.swift
//  PhotomatorSort
//
//  Core data model representing a physical photo grouped with its
//  matching sidecar files (RAW + HEIF + JPEG variants + .photo-edit).
//  All files in a set share the same base filename.
//
//  Future expansion: add `tags`, `cameraModel`, `lensModel` properties
//  when Tag Profiles and Metadata-Aware Smart Exporting modules land.

import Foundation

struct PhotoSetMediaFormats: Hashable, Sendable {
    let isRaw: Bool
    let isHeif: Bool
    let isJpeg: Bool
}

/// Stable identifier for a photographed subject across multiple file formats.
struct PhotoSet: Identifiable, Hashable, Sendable {

    // MARK: - Identity

    let id: UUID
    let baseName: String                     // e.g. "DSCF0142" — the stable grouping key

    /// RAW/HEIF/JPEG source files for this photo set.
    var mediaFiles: [URL]

    /// Photomator `.photo-edit` sidecar bundle, if present.
    var editPath: URL?

    // MARK: - User state

    /// Whether the user has selected this PhotoSet in the grid.
    var isSelected: Bool = false
    
    /// User's star rating (1-5, or 0/nil for unrated)
    var rating: Int? = nil
    
    /// User's flag/pick status (-1 = reject, 0 = unflagged, 1 = flagged)
    var pick: Int? = nil

    // MARK: - Cached stored properties
    let displayName: String
    let preferredPreviewURL: URL?
    let mediaFormats: PhotoSetMediaFormats
    let formatLabel: String

    // MARK: - Computed properties

    /// Whether Photomator has produced an edit sidecar for this photo.
    var hasEdit: Bool { editPath != nil }

    /// All files that would be transferred (media + sidecar).
    var allFiles: [URL] {
        var result = mediaFiles
        if let editPath { result.append(editPath) }
        return result
    }

    /// The count of media files (RAW/HEIF/JPEG) in this set.
    var mediaCount: Int { mediaFiles.count }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        baseName: String,
        mediaFiles: [URL],
        editPath: URL?
    ) {
        self.id = id
        self.baseName = baseName
        let sortedFiles = mediaFiles.sorted { $0.path < $1.path }
        self.mediaFiles = sortedFiles
        self.editPath = editPath

        self.displayName = baseName.replacingOccurrences(of: "_", with: " ")
                                   .replacingOccurrences(of: "-", with: " ")

        self.preferredPreviewURL = sortedFiles.sorted { lhs, rhs in
            Self.previewRank(for: lhs) < Self.previewRank(for: rhs)
        }.first

        let extensions = Set(sortedFiles.map { $0.pathExtension.lowercased() })
        var hasRaw = false
        var hasJpeg = false
        var hasHeif = false
        for ext in extensions {
            if FileExtension.rawLikeExtensions.contains(ext) {
                hasRaw = true
            } else if ["jpg", "jpeg"].contains(ext) {
                hasJpeg = true
            } else if ["heic", "heif", "hif"].contains(ext) {
                hasHeif = true
            }
        }
        self.mediaFormats = PhotoSetMediaFormats(isRaw: hasRaw, isHeif: hasHeif, isJpeg: hasJpeg)

        var parts: [String] = []
        if hasRaw { parts.append("RAW") }
        if hasHeif { parts.append("HEIF") }
        if hasJpeg { parts.append("JPEG") }
        if parts.isEmpty {
            self.formatLabel = "MEDIA"
        } else {
            self.formatLabel = parts.joined(separator: " + ")
        }
    }

    // MARK: - Hashable / Equatable

    nonisolated static func == (lhs: PhotoSet, rhs: PhotoSet) -> Bool {
        lhs.id == rhs.id &&
        lhs.isSelected == rhs.isSelected &&
        lhs.rating == rhs.rating &&
        lhs.pick == rhs.pick &&
        lhs.mediaFiles == rhs.mediaFiles &&
        lhs.editPath == rhs.editPath
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(isSelected)
        hasher.combine(rating)
        hasher.combine(pick)
        hasher.combine(mediaFiles)
        hasher.combine(editPath)
    }

    private static func previewRank(for url: URL) -> Int {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg":
            return 0
        case "hif":
            return 1
        case "raf", "raw":
            return 2
        default:
            return 3
        }
    }
}
