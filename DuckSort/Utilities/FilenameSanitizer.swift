//
//  FilenameSanitizer.swift
//  PhotomatorSort
//

import Foundation

enum FilenameSanitizer {
    static func clean(_ value: String, fallback: String = "Unknown") -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }

        let illegal = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        var result = ""
        result.reserveCapacity(trimmed.count)
        for scalar in trimmed.unicodeScalars {
            result.unicodeScalars.append(illegal.contains(scalar) ? "-" : scalar)
        }
        // Collapse runs of spaces. Two passes max because each replacement
        // can only reduce a 3+ space run by one; in practice filenames
        // rarely have more than two consecutive spaces.
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

