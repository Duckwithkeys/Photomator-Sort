//
//  VCardImport.swift
//  DuckSort
//
//  Helper for reading vCard (.vCard) files into a list of contact names.
//  Used by TagManagerView's Import Contacts button and by the onboarding
//  wizard's tag-pack step.
//

import Foundation
import AppKit
import UniformTypeIdentifiers

enum VCardImport {
    /// Parse the "FN" (formatted name) lines out of a vCard text payload
    /// and return them sorted, deduplicated, with whitespace trimmed.
    static func parseNames(in content: String) -> [String] {
        var names: [String] = []
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.uppercased().hasPrefix("FN:") {
                let name = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { names.append(name) }
            } else if trimmed.uppercased().hasPrefix("FN;") {
                let parts = trimmed.split(separator: ":", maxSplits: 1)
                if parts.count == 2 {
                    let name = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty { names.append(name) }
                }
            }
        }
        return Array(Set(names)).sorted()
    }

    /// Show an `NSOpenPanel` for selecting a single .vCard file. Returns the
    /// file's parsed names on success, or `nil` if the user cancelled.
    @MainActor
    static func promptAndParse() -> [String]? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.vCard]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "Import Contacts"
        panel.prompt = "Import"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }
        return parseNames(in: content)
    }
}