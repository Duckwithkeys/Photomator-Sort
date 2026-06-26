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
    /// All files that would be transferred (media + sidecar). Computed once
    /// at init — `editPath` is never mutated after construction so this is
    /// safe to cache.
    let allFiles: [URL]
    /// Structured breakdown of every file the set owns, tagged with the
    /// role it plays. Used by the large image viewer's metadata sidebar.
    let fileBreakdown: [FileBreakdownEntry]

    // MARK: - Computed properties

    /// Whether Photomator has produced an edit sidecar for this photo.
    var hasEdit: Bool { editPath != nil }

    private static func role(for url: URL) -> FileBreakdownEntry.Role {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg":                       return .jpeg
        case "heic", "heif", "hif":                return .heif
        case "raf":                                return .raw(.fuji)
        case "arw":                                return .raw(.sony)
        case "cr2":                                return .raw(.canonCR2)
        case "cr3":                                return .raw(.canonCR3)
        case "nef":                                return .raw(.nikon)
        case "dng":                                return .raw(.adobe)
        case "orf":                                return .raw(.olympus)
        case "rw2":                                return .raw(.panasonic)
        case "pef":                                return .raw(.pentax)
        case "raw":                                return .raw(.generic)
        default:                                   return .other
        }
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

        self.preferredPreviewURL = sortedFiles.min { lhs, rhs in
            Self.previewRank(for: lhs) < Self.previewRank(for: rhs)
        }

        let extensions = Set(sortedFiles.map { $0.pathExtension.lowercased() })
        var hasRaw = false
        var hasJpeg = false
        var hasHeif = false
        for ext in extensions {
            // Order matters: HEIF/JPEG/PDF must be checked before
            // `rawLikeExtensions` because `.heic`/`.heif`/`.hif` are
            // listed in `rawLikeExtensions` for thumbnail decode purposes
            // (they need the full-decode path). For *format classification*
            // we want HEIF to be its own bucket so a RAW + HEIF set
            // reports `formatLabel = "RAW + HEIF"`, not "RAW".
            if ["jpg", "jpeg"].contains(ext) {
                hasJpeg = true
            } else if ["heic", "heif", "hif"].contains(ext) {
                hasHeif = true
            } else if FileExtension.rawLikeExtensions.contains(ext) {
                hasRaw = true
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

        // Cache allFiles (media + edit sidecar) once. `editPath` is never
        // mutated after init, so this is safe to store as a `let`.
        var all = sortedFiles
        if let editPath { all.append(editPath) }
        self.allFiles = all

        // Cache fileBreakdown once. The role lookup is cheap but called
        // from the large viewer's metadata sidebar on every focused-photo
        // change, so storing it avoids the per-render array allocation.
        var entries: [FileBreakdownEntry] = []
        entries.reserveCapacity(sortedFiles.count + (editPath == nil ? 0 : 1))
        for url in sortedFiles {
            entries.append(FileBreakdownEntry(url: url, role: Self.role(for: url)))
        }
        if let editPath {
            entries.append(FileBreakdownEntry(url: editPath, role: .edit))
        }
        self.fileBreakdown = entries
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
        case "heic", "heif", "hif":
            // HEIF carries a usable embedded preview so it can stand in for
            // the RAW when no JPEG sibling is present.
            return 1
        case "raf", "raw":
            return 2
        default:
            return 3
        }
    }
}

// MARK: - File breakdown

/// One row in the large-viewer "Files in Set" panel. Each entry pairs the
/// actual file URL with the role that file plays in the set so the UI can
/// render a coloured chip (RAW / JPEG / HEIF / .photo-edit / other).
struct FileBreakdownEntry: Identifiable, Hashable {
    enum RawVendor: String, Hashable {
        case fuji, sony, canonCR2, canonCR3, nikon
        case adobe, olympus, panasonic, pentax, generic
    }

    enum Role: Hashable {
        case jpeg
        case heif
        case raw(RawVendor)
        case edit
        case other
    }

    let url: URL
    let role: Role

    var id: URL { url }

    /// Filename only, used by the sidebar so the user can scan file types
    /// at a glance (e.g. "DSCF0142.RAW", "DSCF0142.JPG").
    var displayName: String { url.lastPathComponent }

    /// Short, uppercase label for the role chip.
    var roleLabel: String {
        switch role {
        case .jpeg:        return "JPEG"
        case .heif:        return "HEIF"
        case .raw(let v):  return v.shortLabel
        case .edit:        return "EDIT"
        case .other:       return "FILE"
        }
    }
}

extension FileBreakdownEntry.RawVendor {
    var shortLabel: String {
        switch self {
        case .fuji:        return "RAW · FUJI"
        case .sony:        return "RAW · SONY"
        case .canonCR2:    return "RAW · CANON"
        case .canonCR3:    return "RAW · CANON"
        case .nikon:       return "RAW · NIKON"
        case .adobe:       return "RAW · DNG"
        case .olympus:     return "RAW · OLYMPUS"
        case .panasonic:   return "RAW · PANASONIC"
        case .pentax:      return "RAW · PENTAX"
        case .generic:     return "RAW"
        }
    }
}
