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
import ImageIO

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

    /// Update permanent tags (rating and pick) directly in the photo set's sidecars.
    func updatePermanentTags(rating: Int?, pick: Int?, for photoSet: PhotoSet) throws {
        let urls = xmpSidecarURLs(for: photoSet)
        guard !urls.isEmpty else { return }
        
        let fm = FileManager.default
        for url in urls {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            
            var content: String? = nil
            if fm.fileExists(atPath: url.path) {
                content = try? String(contentsOf: url, encoding: .utf8)
            }
            
            var attrs: [String: String] = [:]
            if let r = rating { attrs["xmp:Rating"] = String(r) }
            if let p = pick { attrs["xmpDM:pick"] = String(p) }
            
            let finalXMP: String
            if let originalXMP = content {
                finalXMP = Self.mergeAttributes(attrs, into: originalXMP)
            } else {
                let payload = SidecarPayload(tagNames: [], capture: MetadataSnapshot(rating: rating, pick: pick))
                finalXMP = Self.exportXMP(payload)
            }
            
            try finalXMP.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// Read tags, rating, and pick from a sidecar if it exists.
    func readSidecarData(from photoSet: PhotoSet) -> (tags: Set<String>, rating: Int?, pick: Int?) {
        for url in xmpSidecarURLs(for: photoSet) {
            if let data = readDataFromXMP(at: url) {
                return data
            }
        }
        return ([], nil, nil)
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

    private func readDataFromXMP(at url: URL) -> (tags: Set<String>, rating: Int?, pick: Int?)? {
        guard FileManager.default.fileExists(atPath: url.path),
              let content = try? String(contentsOf: url, encoding: .utf8)
        else { return nil }

        var names: Set<String> = []
        let subjectPattern = #"(?i)<dc:subject[^>]*>(.*?)</dc:subject>"#
        if let subjectRegex = try? NSRegularExpression(pattern: subjectPattern, options: [.dotMatchesLineSeparators]),
           let subjectMatch = subjectRegex.firstMatch(in: content, options: [], range: NSRange(content.startIndex..., in: content)),
           let subjectRange = Range(subjectMatch.range(at: 1), in: content) {
            
            let subjectBlock = String(content[subjectRange])
            let liPattern = #"<rdf:li[^>]*>(.*?)</rdf:li>"#
            if let liRegex = try? NSRegularExpression(pattern: liPattern, options: [.dotMatchesLineSeparators]) {
                let range = NSRange(subjectBlock.startIndex..., in: subjectBlock)
                liRegex.enumerateMatches(in: subjectBlock, options: [], range: range) { match, _, _ in
                    guard let match, let r = Range(match.range(at: 1), in: subjectBlock) else { return }
                    let raw = String(subjectBlock[r])
                    let cleaned = XMPTaggingService.unescape(raw)
                    if !cleaned.isEmpty { names.insert(cleaned) }
                }
            }
        }

        var rating: Int? = nil
        let attrPattern = #"\b(?:xmp:)?Rating\s*=\s*["']([0-5])["']"#
        if let regex = try? NSRegularExpression(pattern: attrPattern, options: []),
           let match = regex.firstMatch(in: content, options: [], range: NSRange(content.startIndex..., in: content)),
           let range = Range(match.range(at: 1), in: content),
           let val = Int(content[range]) {
            rating = val
        } else {
            let tagPattern = #"<(?:xmp:)?Rating\b[^>]*>([0-5])</(?:xmp:)?Rating>"#
            if let regex = try? NSRegularExpression(pattern: tagPattern, options: []),
               let match = regex.firstMatch(in: content, options: [], range: NSRange(content.startIndex..., in: content)),
               let range = Range(match.range(at: 1), in: content),
               let val = Int(content[range]) {
                rating = val
            }
        }

        var pick: Int? = nil
        let pickAttrPattern = #"\bxmpDM:pick\s*=\s*["'](-?[0-1])["']"#
        if let regex = try? NSRegularExpression(pattern: pickAttrPattern, options: []),
           let match = regex.firstMatch(in: content, options: [], range: NSRange(content.startIndex..., in: content)),
           let range = Range(match.range(at: 1), in: content),
           let val = Int(content[range]) {
            pick = val
        } else {
            let pickTagPattern = #"<xmpDM:pick\b[^>]*>(-?[0-1])</xmpDM:pick>"#
            if let regex = try? NSRegularExpression(pattern: pickTagPattern, options: []),
               let match = regex.firstMatch(in: content, options: [], range: NSRange(content.startIndex..., in: content)),
               let range = Range(match.range(at: 1), in: content),
               let val = Int(content[range]) {
                pick = val
            }
        }
        
        return (names, rating, pick)
    }

    // MARK: - Export sidecars

    /// Destination sidecar URL for a media file (BASENAME.xmp).
    nonisolated static func exportSidecarURL(for fileURL: URL) -> URL {
        fileURL.deletingPathExtension().appendingPathExtension("xmp")
    }

    /// Write an export sidecar beside a destination media file, recording both
    /// custom tag keywords and capture metadata. If a source sidecar exists, we
    /// load it and merge the new metadata, preserving all other existing tags (like ratings).
    func writeExportSidecar(_ payload: SidecarPayload, besideDestinationFile fileURL: URL, mergingSourceSidecar sourceSidecarURL: URL? = nil) throws {
        let url = Self.exportSidecarURL(for: fileURL)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )

        var xmpContent: String? = nil
        if let sourceSidecarURL, FileManager.default.fileExists(atPath: sourceSidecarURL.path) {
            xmpContent = try? String(contentsOf: sourceSidecarURL, encoding: .utf8)
        }

        let finalXMP: String
        if let originalXMP = xmpContent {
            finalXMP = Self.mergePayload(payload, into: originalXMP)
        } else {
            finalXMP = Self.exportXMP(payload)
        }

        try finalXMP.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Merge custom tag keywords into a CGImage properties dictionary as IPTC
    /// Keywords, for embedding in a re-encoded JPEG. Returns the dictionary
    /// unchanged when there are no tags.
    nonisolated static func mergingKeywords(
        _ tagNames: Set<String>,
        into properties: [CFString: Any]
    ) -> [CFString: Any] {
        guard !tagNames.isEmpty else { return properties }
        var result = properties
        var iptc = (result[kCGImagePropertyIPTCDictionary] as? [CFString: Any]) ?? [:]
        iptc[kCGImagePropertyIPTCKeywords] = tagNames.sorted()
        result[kCGImagePropertyIPTCDictionary] = iptc
        return result
    }

    private static func mergePayload(_ payload: SidecarPayload, into content: String) -> String {
        var updated = content
        let sortedNames = payload.tagNames.sorted()
        if !sortedNames.isEmpty {
            let keywords = sortedNames
                .map { "<rdf:li>\(escape($0))</rdf:li>" }
                .joined(separator: "\n                ")
            let subjectBlock = """
            <dc:subject>
                    <rdf:Bag>
                      \(keywords)
                    </rdf:Bag>
                  </dc:subject>
            """
            
            if let merged = tryMergeSubjectStatic(subjectBlock, into: updated) {
                updated = merged
            }
        }
        
        var attrs: [String: String] = [:]
        if let v = payload.capture.cameraModel { attrs["tiff:Model"] = v }
        if let v = payload.capture.lensModel { attrs["exif:LensModel"] = v }
        if let v = payload.capture.aperture { attrs["exif:FNumber"] = formatNumber(v) }
        if let v = payload.capture.shutterSpeed { attrs["exif:ExposureTime"] = formatNumber(v) }
        if let v = payload.capture.iso { attrs["exif:ISOSpeedRatings"] = String(v) }
        if let date = payload.capture.captureDate { attrs["exif:DateTimeOriginal"] = iso8601.string(from: date) }
        if let rating = payload.capture.rating { attrs["xmp:Rating"] = String(rating) }
        if let pick = payload.capture.pick { attrs["xmpDM:pick"] = String(pick) }
        
        updated = mergeAttributes(attrs, into: updated)
        return updated
    }

    private static func mergeAttributes(_ attrs: [String: String], into content: String) -> String {
        var updated = content
        let namespaces = [
            "xmlns:tiff": "http://ns.adobe.com/tiff/1.0/",
            "xmlns:exif": "http://ns.adobe.com/exif/1.0/",
            "xmlns:xmp": "http://ns.adobe.com/xap/1.0/",
            "xmlns:xmpDM": "http://ns.adobe.com/xmp/1.0/DynamicMedia/"
        ]
        
        let descPattern = #"(?i)(<rdf:Description\b[^>]*>)"#
        guard let regex = try? NSRegularExpression(pattern: descPattern, options: []),
              let match = regex.firstMatch(in: updated, options: [], range: NSRange(updated.startIndex..., in: updated)),
              let matchRange = Range(match.range(at: 1), in: updated)
        else {
            return updated
        }
        
        var tagContent = String(updated[matchRange])
        
        for (prefix, uri) in namespaces {
            if !tagContent.contains(prefix) {
                if tagContent.hasSuffix("/>") {
                    tagContent = tagContent.replacingOccurrences(of: "/>", with: " \(prefix)=\"\(uri)\"/>")
                } else if tagContent.hasSuffix(">") {
                    tagContent = tagContent.replacingOccurrences(of: ">", with: " \(prefix)=\"\(uri)\">")
                }
            }
        }
        
        for (attrName, attrValue) in attrs {
            let escapedVal = escape(attrValue)
            let attrPattern = "\(attrName)\\s*=\\s*\"[^\"]*\"|\(attrName)\\s*=\\s*'[^']*'"
            if let attrRegex = try? NSRegularExpression(pattern: attrPattern, options: []) {
                let range = NSRange(tagContent.startIndex..., in: tagContent)
                if attrRegex.firstMatch(in: tagContent, options: [], range: range) != nil {
                    tagContent = attrRegex.stringByReplacingMatches(
                        in: tagContent, options: [], range: range, withTemplate: "\(attrName)=\"\(escapedVal)\""
                    )
                } else {
                    if tagContent.hasSuffix("/>") {
                        tagContent = tagContent.replacingOccurrences(of: "/>", with: " \(attrName)=\"\(escapedVal)\"/>")
                    } else if tagContent.hasSuffix(">") {
                        tagContent = tagContent.replacingOccurrences(of: ">", with: " \(attrName)=\"\(escapedVal)\">")
                    }
                }
            }
        }
        
        updated.replaceSubrange(matchRange, with: tagContent)
        return updated
    }

    private static func tryMergeSubjectStatic(_ subjectBlock: String, into content: String) -> String? {
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

    private static func exportXMP(_ payload: SidecarPayload) -> String {
        var attrs: [String] = []
        if let v = payload.capture.cameraModel { attrs.append("tiff:Model=\"\(escape(v))\"") }
        if let v = payload.capture.lensModel { attrs.append("exif:LensModel=\"\(escape(v))\"") }
        if let v = payload.capture.aperture { attrs.append("exif:FNumber=\"\(formatNumber(v))\"") }
        if let v = payload.capture.shutterSpeed { attrs.append("exif:ExposureTime=\"\(formatNumber(v))\"") }
        if let v = payload.capture.iso { attrs.append("exif:ISOSpeedRatings=\"\(v)\"") }
        if let date = payload.capture.captureDate {
            attrs.append("exif:DateTimeOriginal=\"\(iso8601.string(from: date))\"")
        }
        if let v = payload.capture.rating { attrs.append("xmp:Rating=\"\(v)\"") }
        if let v = payload.capture.pick { attrs.append("xmpDM:pick=\"\(v)\"") }
        let captureAttrs = attrs.isEmpty ? "" : "\n          " + attrs.joined(separator: "\n          ")

        let subjectBlock: String
        let sortedNames = payload.tagNames.sorted()
        if sortedNames.isEmpty {
            subjectBlock = ""
        } else {
            let keywords = sortedNames
                .map { "<rdf:li>\(escape($0))</rdf:li>" }
                .joined(separator: "\n                ")
            subjectBlock = """

              <dc:subject>
                <rdf:Bag>
                  \(keywords)
                </rdf:Bag>
              </dc:subject>
            """
        }

        return """
        <?xpacket begin="" id="W5M0MpCehiHzreSzNTczkc9d"?>
        <x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="DuckSort">
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description
              xmlns:dc="http://purl.org/dc/elements/1.1/"
              xmlns:tiff="http://ns.adobe.com/tiff/1.0/"
              xmlns:exif="http://ns.adobe.com/exif/1.0/"
              xmlns:xmp="http://ns.adobe.com/xap/1.0/"
              xmlns:xmpDM="http://ns.adobe.com/xmp/1.0/DynamicMedia/"\(captureAttrs)>\(subjectBlock)
            </rdf:Description>
          </rdf:RDF>
        </x:xmpmeta>
        <?xpacket end="r"?>
        """
    }

    private static func formatNumber(_ value: Double) -> String {
        if value == value.rounded() { return String(Int(value)) }
        return String(format: "%.4g", value)
    }

    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    // MARK: - XML escaping

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
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
