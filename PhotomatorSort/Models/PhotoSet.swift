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

    // MARK: - Computed properties

    /// Whether Photomator has produced an edit sidecar for this photo.
    var hasEdit: Bool { editPath != nil }

    /// All files that would be transferred (media + sidecar).
    var allFiles: [URL] {
        var result = mediaFiles
        if let editPath { result.append(editPath) }
        return result
    }

    /// Filename suitable for display in the UI grid.
    var displayName: String {
        baseName.replacingOccurrences(of: "_", with: " ")
                 .replacingOccurrences(of: "-", with: " ")
    }

    /// The count of media files (RAW/HEIF/JPEG) in this set.
    var mediaCount: Int { mediaFiles.count }

    /// Prefer already-rendered formats for faster thumbnails before falling back to RAW.
    var preferredPreviewURL: URL? {
        mediaFiles.sorted { lhs, rhs in
            Self.previewRank(for: lhs) < Self.previewRank(for: rhs)
        }.first
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        baseName: String,
        mediaFiles: [URL],
        editPath: URL?
    ) {
        self.id = id
        self.baseName = baseName
        self.mediaFiles = mediaFiles.sorted { $0.path < $1.path }
        self.editPath = editPath
    }

    // MARK: - Hashable / Equatable

    nonisolated static func == (lhs: PhotoSet, rhs: PhotoSet) -> Bool {
        lhs.id == rhs.id
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
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
