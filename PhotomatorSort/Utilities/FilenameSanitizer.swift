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
        let parts = trimmed.components(separatedBy: illegal)
        return parts
            .joined(separator: "-")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

