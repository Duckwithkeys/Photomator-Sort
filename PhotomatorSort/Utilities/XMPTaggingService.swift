//
//  XMPTaggingService.swift
//  PhotomatorSort
//
//  Reads and writes custom user tag keywords into XMP sidecar files
//  (one .xmp per media file in a PhotoSet). Writes dc:subject keywords
//  using the human-readable tag names so they appear in any DAM / editor
//  that reads standard XMP.
//

import Foundation

actor XMPTaggingService {

    /// Apply the given tag names to every XMP sidecar belonging to the photo set.
    /// Tag names are written as <dc:subject> <rdf:li> entries so apps like
    /// Photomator, Lightroom, and Bridge can read them.
    func applyTagNames(_ tagNames: Set<String>, to photoSet: PhotoSet) throws {
        let urls = xmpSidecarURLs(for: photoSet)
        guard !urls.isEmpty else { return }
        for url in urls {
            try writeSidecar(tagNames: tagNames, to: url)
        }
    }

    /// Remove the XMP sidecar for the photo set (used when tags are cleared).
    func clear(for photoSet: PhotoSet) throws {
        let fm = FileManager.default
        for url in xmpSidecarURLs(for: photoSet) where fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
    }

    /// Read tag names previously written to a sidecar. Returns an empty set
    /// if no sidecar exists.
    func readTagNames(from photoSet: PhotoSet) -> Set<String> {
        for url in xmpSidecarURLs(for: photoSet) {
            if let names = readTagNamesFromXMP(at: url) {
                return names
            }
        }
        return []
    }

    // MARK: - Sidecar URLs

    private func xmpSidecarURLs(for photoSet: PhotoSet) -> [URL] {
        let mediaSidecars = photoSet.mediaFiles.map {
            $0.deletingPathExtension().appendingPathExtension("xmp")
        }
        let editSidecar = photoSet.editPath.map {
            $0.deletingLastPathComponent()
                .appendingPathComponent(photoSet.baseName)
                .appendingPathExtension("xmp")
        }
        return Array(Set(mediaSidecars + [editSidecar].compactMap { $0 }))
            .sorted { $0.path < $1.path }
    }

    // MARK: - Write

    private func writeSidecar(tagNames: Set<String>, to url: URL) throws {
        let sortedNames = tagNames.sorted()
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        if sortedNames.isEmpty {
            if fm.fileExists(atPath: url.path) {
                let content = try String(contentsOf: url, encoding: .utf8)
                if let updated = tryRemoveSubject(from: content) {
                    try updated.write(to: url, atomically: true, encoding: .utf8)
                } else {
                    try fm.removeItem(at: url)
                }
            }
            return
        }

        let keywords = sortedNames
            .map { "<rdf:li>\(Self.escape($0))</rdf:li>" }
            .joined(separator: "\n                  ")

        let subjectBlock = """
        <dc:subject>
                <rdf:Bag>
                  \(keywords)
                </rdf:Bag>
              </dc:subject>
        """

        if fm.fileExists(atPath: url.path) {
            let content = try String(contentsOf: url, encoding: .utf8)
            if let mergedXMP = tryMergeSubject(subjectBlock, into: content) {
                try mergedXMP.write(to: url, atomically: true, encoding: .utf8)
                return
            }
        }

        let xmp = """
        <?xpacket begin="" id="W5M0MpCehiHzreSzNTczkc9d"?>
        <x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="PhotomatorSort">
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description xmlns:dc="http://purl.org/dc/elements/1.1/">
              \(subjectBlock)
            </rdf:Description>
          </rdf:RDF>
        </x:xmpmeta>
        <?xpacket end="r"?>
        """

        try xmp.write(to: url, atomically: true, encoding: .utf8)
    }

    private func tryMergeSubject(_ subjectBlock: String, into content: String) -> String? {
        let subjectPattern = #"(?i)<dc:subject[^>]*>.*?</dc:subject>"#
        if let regex = try? NSRegularExpression(pattern: subjectPattern, options: [.dotMatchesLineSeparators]) {
            let range = NSRange(content.startIndex..., in: content)
            if regex.firstMatch(in: content, options: [], range: range) != nil {
                let modified = regex.stringByReplacingMatches(in: content, options: [], range: range, withTemplate: subjectBlock)
                return modified
            }
        }

        let descPattern = #"(?i)(<rdf:Description[^>]*>)"#
        if let regex = try? NSRegularExpression(pattern: descPattern, options: []) {
            let range = NSRange(content.startIndex..., in: content)
            if let match = regex.firstMatch(in: content, options: [], range: range),
               let matchRange = Range(match.range(at: 1), in: content) {
                
                let matchedTag = String(content[matchRange])
                if matchedTag.hasSuffix("/>") {
                    let cleanedTag = matchedTag.trimmingCharacters(in: CharacterSet(charactersIn: "/> "))
                    let replacement = "<\(cleanedTag)>\n      \(subjectBlock)\n    </rdf:Description>"
                    return content.replacingOccurrences(of: matchedTag, with: replacement)
                } else {
                    let replacement = "\(matchedTag)\n      \(subjectBlock)"
                    return content.replacingOccurrences(of: matchedTag, with: replacement)
                }
            }
        }

        return nil
    }

    private func tryRemoveSubject(from content: String) -> String? {
        let subjectPattern = #"(?i)<dc:subject[^>]*>.*?</dc:subject>\n?"#
        if let regex = try? NSRegularExpression(pattern: subjectPattern, options: [.dotMatchesLineSeparators]) {
            let range = NSRange(content.startIndex..., in: content)
            if regex.firstMatch(in: content, options: [], range: range) != nil {
                let modified = regex.stringByReplacingMatches(in: content, options: [], range: range, withTemplate: "")
                return modified
            }
        }
        return nil
    }

    // MARK: - Read

    private func readTagNamesFromXMP(at url: URL) -> Set<String>? {
        guard FileManager.default.fileExists(atPath: url.path),
              let content = try? String(contentsOf: url, encoding: .utf8)
        else { return nil }

        let subjectPattern = #"(?i)<dc:subject[^>]*>(.*?)</dc:subject>"#
        guard let subjectRegex = try? NSRegularExpression(pattern: subjectPattern, options: [.dotMatchesLineSeparators]),
              let subjectMatch = subjectRegex.firstMatch(in: content, options: [], range: NSRange(content.startIndex..., in: content)),
              let subjectRange = Range(subjectMatch.range(at: 1), in: content)
        else {
            return nil
        }
        
        let subjectBlock = String(content[subjectRange])

        var names: Set<String> = []
        let liPattern = #"<rdf:li[^>]*>(.*?)</rdf:li>"#
        guard let liRegex = try? NSRegularExpression(pattern: liPattern, options: [.dotMatchesLineSeparators]) else {
            return nil
        }

        let range = NSRange(subjectBlock.startIndex..., in: subjectBlock)
        liRegex.enumerateMatches(in: subjectBlock, options: [], range: range) { match, _, _ in
            guard let match,
                  let r = Range(match.range(at: 1), in: subjectBlock)
            else { return }
            let raw = String(subjectBlock[r])
            let cleaned = XMPTaggingService.unescape(raw)
            if !cleaned.isEmpty {
                names.insert(cleaned)
            }
        }

        return names.isEmpty ? nil : names
    }

    // MARK: - XML escaping

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func unescape(_ value: String) -> String {
        var s = value
        s = s.replacingOccurrences(of: "&lt;", with: "<")
        s = s.replacingOccurrences(of: "&gt;", with: ">")
        s = s.replacingOccurrences(of: "&quot;", with: "\"")
        s = s.replacingOccurrences(of: "&apos;", with: "'")
        s = s.replacingOccurrences(of: "&amp;", with: "&")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
