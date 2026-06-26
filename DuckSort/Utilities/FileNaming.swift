//
//  FileNaming.swift
//  DuckSort
//
//  Shared naming helpers for transfer destinations. Extracted so any future
//  optimization applies to every transfer path (plain + routed) at once.
//

import Foundation

enum FileNaming {
    /// Build a unique destination URL inside `directory` for `sourceURL`.
    /// If `sourceURL` already lives directly in `directory` (i.e. copying
    /// or moving onto itself), returns the original. If the candidate path
    /// is free, returns it. Otherwise, appends `-1`, `-2`, … until an
    /// unused name is found.
    nonisolated static func uniqueDestinationURL(
        for sourceURL: URL,
        in directory: URL,
        fileManager: FileManager = .default
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
