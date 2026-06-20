//
//  FileGroupingResult.swift
//  PhotomatorSort
//
//  Immutable snapshot of a completed directory scan.
//  Designed so that future modules (tag profiles, EXIF metadata) can add
//  their own fields without changing the core type.

import Foundation

/// Result wrapper from a ``FileScanner`` invocation.
struct FileGroupingResult: Sendable {

    let sourceDirectories: [URL]
    let photoSets: [PhotoSet]

    /// Total number of physical files across all groups (media + sidecars).
    var totalFileCount: Int {
        photoSets.reduce(0) { $0 + $1.mediaFiles.count }
                  + photoSets.filter(\.hasEdit).count
    }

    /// How many sets have a Photomator edit sidecar.
    var editedCount: Int {
        photoSets.filter(\.hasEdit).count
    }

    init(sourceDirectories: [URL], photoSets: [PhotoSet]) {
        self.sourceDirectories = sourceDirectories
        self.photoSets = photoSets
    }
}
