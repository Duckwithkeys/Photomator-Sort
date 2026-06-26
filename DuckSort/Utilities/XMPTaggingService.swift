//
//  XMPTaggingService.swift
//  PhotomatorSort
//
//  Reads and writes custom user tag keywords into XMP sidecar files
//  (one .xmp per media file in a PhotoSet). Writes dc:subject keywords
//  using the human-readable tag names so they appear in any DAM / editor
//  that reads standard XMP.
//
//  Performance notes (applied optimizations):
//  - All NSRegularExpression patterns are pre-compiled once as static
//    `lets` on the type (was 19 inline `try? NSRegularExpression(...)`
//    calls before). See `XMPSchema.Regex`.
//  - This type is a stateless `Sendable struct` (was an `actor`) so the
//    call sites can drop the `await` and sidecar writes run truly in
//    parallel during transfers. PhotoLibraryViewModel.commitTagChange
//    chains tasks sequentially for ordering, so the actor lock was
//    redundant.
//  - `xmpSidecarURLs(for:)` now dedupes incrementally (Set insert) and
//    returns one sorted array, avoiding the old 6-allocation
//    `Array(Set(...))` round-trip.
//  - `escape` and `unescape` are single-pass character scanners
//    (were 4–5 chained `replacingOccurrences` calls each).
//  - `fileExists(atPath:)` followed immediately by `String(contentsOf:)`
//    is collapsed into a single `try? String(contentsOf:)` call.
//

import Foundation
import ImageIO

struct XMPTaggingService: Sendable {

    /// Apply the given tag names to every XMP sidecar belonging to the photo set.
    /// Tag names are written as <dc:subject> <rdf:li> entries so apps like
    /// Photomator, Lightroom, and Bridge can read them.
    func applyTagNames(_ tagNames: Set<String>, to photoSet: PhotoSet) throws {
        let urls = Self.xmpSidecarURLs(for: photoSet)
        guard !urls.isEmpty else { return }
        for url in urls {
            try writeSidecar(tagNames: tagNames, to: url)
        }
    }

    /// Remove the XMP sidecar for the photo set (used when tags are cleared).
    func clear(for photoSet: PhotoSet) throws {
        let urls = Self.xmpSidecarURLs(for: photoSet)
        let fm = FileManager.default
        for url in urls where fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
    }

    /// Update rating + pick values on every sidecar without touching tags.
    func updatePermanentTags(rating: Int?, pick: Int?, for photoSet: PhotoSet) throws {
        let urls = Self.xmpSidecarURLs(for: photoSet)
        guard !urls.isEmpty else { return }

        // Mirror the same path the file scanner does so we touch every
        // sibling that might be associated with this photo set.
        for url in urls {
            try updateSidecarRatingPick(url: url, rating: rating, pick: pick)
        }
    }

    /// Set the caption (dc:description) on every sidecar belonging to the set.
    /// Pass nil to clear the caption from every sidecar.
    func updateCaption(_ caption: String?, for photoSet: PhotoSet) throws {
        let urls = Self.xmpSidecarURLs(for: photoSet)
        guard !urls.isEmpty else { return }
        for url in urls {
            try updateSidecarCaption(url: url, caption: caption)
        }
    }

    /// Read tags, rating, pick, and description from a sidecar if it exists.
    func readSidecarData(from photoSet: PhotoSet) -> (tags: Set<String>, rating: Int?, pick: Int?, description: String?) {
        for url in Self.xmpSidecarURLs(for: photoSet) {
            if let data = readDataFromXMP(at: url) {
                return data
            }
        }
        return ([], nil, nil, nil)
    }

    // MARK: - Sidecar URLs

    nonisolated static func xmpSidecarURLs(for photoSet: PhotoSet) -> [URL] {
        var seen = Set<URL>()
        var result: [URL] = []
        result.reserveCapacity(photoSet.mediaFiles.count + 1)

        for file in photoSet.mediaFiles {
            let sidecar = file.deletingPathExtension().appendingPathExtension("xmp")
            if seen.insert(sidecar).inserted { result.append(sidecar) }
        }

        if let editPath = photoSet.editPath {
            let editSidecar = editPath.deletingLastPathComponent()
                .appendingPathComponent(photoSet.baseName)
                .appendingPathExtension("xmp")
            if seen.insert(editSidecar).inserted { result.append(editSidecar) }
        }

        result.sort { $0.path < $1.path }
        return result
    }

    // MARK: - Write

    private func writeSidecar(tagNames: Set<String>, to url: URL) throws {
        let sortedNames = tagNames.sorted()
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        if sortedNames.isEmpty {
            if let content = try? String(contentsOf: url, encoding: .utf8),
               let updated = Self.tryRemoveSubject(from: content) {
                try updated.write(to: url, atomically: true, encoding: .utf8)
            } else if fm.fileExists(atPath: url.path) {
                try fm.removeItem(at: url)
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

        if let content = try? String(contentsOf: url, encoding: .utf8),
           let mergedXMP = Self.tryMergeSubject(subjectBlock, into: content) {
            try mergedXMP.write(to: url, atomically: true, encoding: .utf8)
            return
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

    nonisolated private static func tryMergeSubject(_ subjectBlock: String, into content: String) -> String? {
        let range = NSRange(content.startIndex..., in: content)
        if Regex.subjectFull.firstMatch(in: content, options: [], range: range) != nil {
            return Regex.subjectFull.stringByReplacingMatches(
                in: content, options: [], range: range, withTemplate: subjectBlock
            )
        }

        if let match = Regex.descriptionTag.firstMatch(in: content, options: [], range: range),
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

        return nil
    }

    nonisolated private static func tryRemoveSubject(from content: String) -> String? {
        let range = NSRange(content.startIndex..., in: content)
        guard Regex.subjectRemove.firstMatch(in: content, options: [], range: range) != nil else {
            return nil
        }
        return Regex.subjectRemove.stringByReplacingMatches(in: content, options: [], range: range, withTemplate: "")
    }

    private func updateSidecarRatingPick(url: URL, rating: Int?, pick: Int?) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            // Nothing to update; sidecar doesn't exist yet.
            return
        }
        var content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        if let rating {
            content = Self.upsertAttribute(name: "xmp:Rating", value: String(rating), in: content)
        }
        if let pick {
            content = Self.upsertAttribute(name: "xmpDM:pick", value: String(pick), in: content)
        }
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    private func updateSidecarCaption(url: URL, caption: String?) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return }
        var content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        content = Self.mergeDescription(caption, into: content)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Read

    private func readDataFromXMP(at url: URL) -> (tags: Set<String>, rating: Int?, pick: Int?, description: String?)? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }

        var names: Set<String> = []
        let contentRange = NSRange(content.startIndex..., in: content)
        if let subjectMatch = Regex.subjectContent.firstMatch(in: content, options: [], range: contentRange),
           let subjectRange = Range(subjectMatch.range(at: 1), in: content) {

            let subjectBlock = String(content[subjectRange])
            let blockRange = NSRange(subjectBlock.startIndex..., in: subjectBlock)
            Regex.liItem.enumerateMatches(in: subjectBlock, options: [], range: blockRange) { match, _, _ in
                guard let match, let r = Range(match.range(at: 1), in: subjectBlock) else { return }
                let raw = String(subjectBlock[r])
                let cleaned = Self.unescape(raw)
                if !cleaned.isEmpty { names.insert(cleaned) }
            }
        }

        var rating: Int? = nil
        if let match = Regex.ratingAttr.firstMatch(in: content, options: [], range: contentRange),
           let range = Range(match.range(at: 1), in: content),
           let val = Int(content[range]) {
            rating = val
        } else if let match = Regex.ratingTag.firstMatch(in: content, options: [], range: contentRange),
                  let range = Range(match.range(at: 1), in: content),
                  let val = Int(content[range]) {
            rating = val
        }

        var pick: Int? = nil
        if let match = Regex.pickAttr.firstMatch(in: content, options: [], range: contentRange),
           let range = Range(match.range(at: 1), in: content),
           let val = Int(content[range]) {
            pick = val
        } else if let match = Regex.pickTag.firstMatch(in: content, options: [], range: contentRange),
                  let range = Range(match.range(at: 1), in: content),
                  let val = Int(content[range]) {
            pick = val
        }

        let description = Self.extractDescription(from: content)

        return (names, rating, pick, description)
    }

    nonisolated static func extractDescription(from content: String) -> String? {
        let range = NSRange(content.startIndex..., in: content)
        if Regex.descriptionSelfClosing.firstMatch(in: content, options: [], range: range) != nil {
            return ""
        }
        if let match = Regex.descriptionBody.firstMatch(in: content, options: [], range: range),
           match.numberOfRanges >= 2,
           let captureRange = Range(match.range(at: 1), in: content) {
            let raw = String(content[captureRange])
            let cleaned = unescape(raw)
            return cleaned.isEmpty ? nil : cleaned
        }
        return nil
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

        let originalXMP: String? = {
            guard let sourceSidecarURL else { return nil }
            return try? String(contentsOf: sourceSidecarURL, encoding: .utf8)
        }()

        let finalXMP: String
        if let originalXMP {
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

    nonisolated static func mergePayload(_ payload: SidecarPayload, into content: String) -> String {
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

        if let caption = payload.capture.caption {
            updated = mergeDescription(caption, into: updated)
        }

        if payload.iptc != IPTCMetadata() {
            updated = mergeIPTC(payload.iptc, into: updated)
        }

        return updated
    }

    /// Insert, replace, or remove the <dc:description> element in existing XMP content.
    /// Pass nil to remove the description entirely.
    nonisolated static func mergeDescription(_ description: String?, into content: String) -> String {
        var updated = content
        let range = NSRange(updated.startIndex..., in: updated)
        if Regex.descriptionBody.firstMatch(in: updated, options: [], range: range) != nil {
            updated = Regex.descriptionBody.stringByReplacingMatches(
                in: updated, options: [], range: range, withTemplate: ""
            )
        }
        if Regex.descriptionSelfClosing.firstMatch(in: updated, options: [], range: range) != nil {
            updated = Regex.descriptionSelfClosing.stringByReplacingMatches(
                in: updated, options: [], range: range, withTemplate: ""
            )
        }

        guard let description, !description.isEmpty else { return updated }

        let cleaned = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return updated }

        let escaped = escape(cleaned)
        let descriptionBlock = "<dc:description>\n        \(escaped)\n      </dc:description>"

        if let match = Regex.rdfDescriptionClose.firstMatch(in: updated, options: [], range: range),
           let r = Range(match.range, in: updated) {
            updated.replaceSubrange(r, with: "  \(descriptionBlock)\n    </rdf:Description>")
            return updated
        }

        updated += "\n\(descriptionBlock)\n"
        return updated
    }

    /// Insert / replace / remove the IPTC creator, rights, contact, and
    /// usage-terms elements inside an existing XMP packet. Empty fields
    /// are skipped; existing matching elements are replaced so the user's
    /// current settings always win on a re-export.
    nonisolated static func mergeIPTC(_ iptc: IPTCMetadata, into content: String) -> String {
        var updated = content

        let namespacesToDeclare: [(String, String)] = [
            ("xmlns:Iptc4xmpCore", "http://iptc.org/std/Iptc4xmpCore/2008-02-29/"),
            ("xmlns:xmpRights", "http://ns.adobe.com/xap/1.0/rights/")
        ]
        let range = NSRange(updated.startIndex..., in: updated)
        if let match = Regex.descriptionTag.firstMatch(in: updated, options: [], range: range),
           let r = Range(match.range(at: 1), in: updated) {
            var openingTag = String(updated[r])
            for (prefix, uri) in namespacesToDeclare where !openingTag.contains(prefix) {
                if openingTag.hasSuffix("/>") {
                    openingTag = openingTag.replacingOccurrences(of: "/>", with: " \(prefix)=\"\(uri)\"/>")
                } else if openingTag.hasSuffix(">") {
                    openingTag = openingTag.replacingOccurrences(of: ">", with: " \(prefix)=\"\(uri)\">")
                }
            }
            updated.replaceSubrange(r, with: openingTag)
        }

        func upsert(replacingPattern: NSRegularExpression, element: String) {
            let r = NSRange(updated.startIndex..., in: updated)
            if replacingPattern.firstMatch(in: updated, options: [], range: r) != nil {
                updated = replacingPattern.stringByReplacingMatches(
                    in: updated, options: [], range: r, withTemplate: element
                )
                return
            }
            if let match = Regex.rdfDescriptionClose.firstMatch(in: updated, options: [], range: r),
               let rr = Range(match.range, in: updated) {
                updated.replaceSubrange(rr, with: "\n    \(element)\n  </rdf:Description>")
            }
        }

        if let name = iptc.creatorName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            let creatorBlock = """
            <dc:creator>
              <rdf:Seq>
                <rdf:li>\(escape(name))</rdf:li>
              </rdf:Seq>
            </dc:creator>
            """
            upsert(replacingPattern: Regex.dcCreator, element: creatorBlock)
        }

        if let rights = iptc.copyrightNotice?.trimmingCharacters(in: .whitespacesAndNewlines), !rights.isEmpty {
            let rightsBlock = """
            <dc:rights>
              <rdf:Alt>
                <rdf:li xml:lang="x-default">\(escape(rights))</rdf:li>
              </rdf:Alt>
            </dc:rights>
            """
            upsert(replacingPattern: Regex.dcRights, element: rightsBlock)
        }

        if let email = iptc.contactEmail?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty {
            upsert(
                replacingPattern: Regex.iptcEmail,
                element: "<Iptc4xmpCore:CiEmailWork>\(escape(email))</Iptc4xmpCore:CiEmailWork>"
            )
        }

        if let phone = iptc.contactPhone?.trimmingCharacters(in: .whitespacesAndNewlines), !phone.isEmpty {
            upsert(
                replacingPattern: Regex.iptcPhone,
                element: "<Iptc4xmpCore:CiTelWork>\(escape(phone))</Iptc4xmpCore:CiTelWork>"
            )
        }

        if let website = iptc.contactWebsite?.trimmingCharacters(in: .whitespacesAndNewlines), !website.isEmpty {
            upsert(
                replacingPattern: Regex.iptcWebsite,
                element: "<Iptc4xmpCore:CiUrlWork>\(escape(website))</Iptc4xmpCore:CiUrlWork>"
            )
        }

        if let usage = iptc.rightsUsageTerms?.trimmingCharacters(in: .whitespacesAndNewlines), !usage.isEmpty {
            let usageBlock = """
            <xmpRights:UsageTerms>
              <rdf:Alt>
                <rdf:li xml:lang="x-default">\(escape(usage))</rdf:li>
              </rdf:Alt>
            </xmpRights:UsageTerms>
            """
            upsert(replacingPattern: Regex.usageTerms, element: usageBlock)
        }

        return updated
    }

    nonisolated static func iptcFromPreferences() -> IPTCMetadata {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "embedIPTCInExports") else { return IPTCMetadata() }
        return IPTCMetadata(
            creatorName: defaults.string(forKey: "iptcCreatorName")?.nonEmpty,
            copyrightNotice: defaults.string(forKey: "iptcCopyrightNotice")?.nonEmpty,
            contactEmail: defaults.string(forKey: "iptcContactEmail")?.nonEmpty,
            contactPhone: defaults.string(forKey: "iptcContactPhone")?.nonEmpty,
            contactWebsite: defaults.string(forKey: "iptcContactWebsite")?.nonEmpty,
            rightsUsageTerms: defaults.string(forKey: "iptcRightsUsageTerms")?.nonEmpty
        )
    }

    nonisolated static func mergeAttributes(_ attrs: [String: String], into content: String) -> String {
        var updated = content
        let namespaces = [
            "xmlns:tiff": "http://ns.adobe.com/tiff/1.0/",
            "xmlns:exif": "http://ns.adobe.com/exif/1.0/",
            "xmlns:xmp": "http://ns.adobe.com/xap/1.0/",
            "xmlns:xmpDM": "http://ns.adobe.com/xmp/1.0/DynamicMedia/"
        ]

        let range = NSRange(updated.startIndex..., in: updated)
        guard let match = Regex.descriptionTag.firstMatch(in: updated, options: [], range: range),
              let matchRange = Range(match.range(at: 1), in: updated) else {
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
            tagContent = upsertAttribute(name: attrName, value: escapedVal, in: tagContent)
        }

        updated.replaceSubrange(matchRange, with: tagContent)
        return updated
    }

    /// Insert or replace an attribute like `xmp:Rating="5"` inside the
    /// `<rdf:Description>` opening tag's attribute list.
    nonisolated private static func upsertAttribute(name: String, value: String, in content: String) -> String {
        let escaped = "\(name)=\"\(value)\""
        let pattern = "\(name)\\s*=\\s*\"[^\"]*\"|\(name)\\s*=\\s*'[^']*'"
        guard let attrRegex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return content
        }
        let range = NSRange(content.startIndex..., in: content)
        if attrRegex.firstMatch(in: content, options: [], range: range) != nil {
            return attrRegex.stringByReplacingMatches(
                in: content, options: [], range: range, withTemplate: escaped
            )
        }
        if content.hasSuffix("/>") {
            return content.replacingOccurrences(of: "/>", with: " \(escaped)/>")
        }
        if content.hasSuffix(">") {
            return content.replacingOccurrences(of: ">", with: " \(escaped)>")
        }
        return content
    }

    nonisolated private static func tryMergeSubjectStatic(_ subjectBlock: String, into content: String) -> String? {
        tryMergeSubject(subjectBlock, into: content)
    }

    nonisolated static func exportXMP(_ payload: SidecarPayload) -> String {
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

        let descriptionBlock: String
        if let caption = payload.capture.caption?.trimmingCharacters(in: .whitespacesAndNewlines), !caption.isEmpty {
            descriptionBlock = """

              <dc:description>
                \(escape(caption))
              </dc:description>
            """
        } else {
            descriptionBlock = ""
        }

        let iptcBlock: String
        let iptc = payload.iptc
        let hasIPTC = iptc != IPTCMetadata()
        if hasIPTC {
            var iptcElements: [String] = []
            if let name = iptc.creatorName?.trimmingCharacters(in: .whitespacesAndNewlines),
               !name.isEmpty {
                iptcElements.append("""
                  <dc:creator>
                    <rdf:Seq>
                      <rdf:li>\(escape(name))</rdf:li>
                    </rdf:Seq>
                  </dc:creator>
                """)
            }
            if let rights = iptc.copyrightNotice?.trimmingCharacters(in: .whitespacesAndNewlines),
               !rights.isEmpty {
                iptcElements.append("""
                  <dc:rights>
                    <rdf:Alt>
                      <rdf:li xml:lang="x-default">\(escape(rights))</rdf:li>
                    </rdf:Alt>
                  </dc:rights>
                """)
            }
            if let email = iptc.contactEmail?.trimmingCharacters(in: .whitespacesAndNewlines),
               !email.isEmpty {
                iptcElements.append("<Iptc4xmpCore:CiEmailWork>\(escape(email))</Iptc4xmpCore:CiEmailWork>")
            }
            if let phone = iptc.contactPhone?.trimmingCharacters(in: .whitespacesAndNewlines),
               !phone.isEmpty {
                iptcElements.append("<Iptc4xmpCore:CiTelWork>\(escape(phone))</Iptc4xmpCore:CiTelWork>")
            }
            if let website = iptc.contactWebsite?.trimmingCharacters(in: .whitespacesAndNewlines),
               !website.isEmpty {
                iptcElements.append("<Iptc4xmpCore:CiUrlWork>\(escape(website))</Iptc4xmpCore:CiUrlWork>")
            }
            if let usage = iptc.rightsUsageTerms?.trimmingCharacters(in: .whitespacesAndNewlines),
               !usage.isEmpty {
                iptcElements.append("""
                  <xmpRights:UsageTerms>
                    <rdf:Alt>
                      <rdf:li xml:lang="x-default">\(escape(usage))</rdf:li>
                    </rdf:Alt>
                  </xmpRights:UsageTerms>
                """)
            }
            iptcBlock = iptcElements.isEmpty ? "" : "\n          " + iptcElements.joined(separator: "\n          ")
        } else {
            iptcBlock = ""
        }

        let iptcNamespaceDecl = hasIPTC
            ? "\n              xmlns:Iptc4xmpCore=\"http://iptc.org/std/Iptc4xmpCore/2008-02-29/\"\n              xmlns:xmpRights=\"http://ns.adobe.com/xap/1.0/rights/\""
            : ""

        return """
        <?xpacket begin="" id="W5M0MpCehiHzreSzNTczkc9d"?>
        <x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="DuckSort">
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description
              xmlns:dc="http://purl.org/dc/elements/1.1/"
              xmlns:tiff="http://ns.adobe.com/tiff/1.0/"
              xmlns:exif="http://ns.adobe.com/exif/1.0/"
              xmlns:xmp="http://ns.adobe.com/xap/1.0/"
              xmlns:xmpDM="http://ns.adobe.com/xmp/1.0/DynamicMedia/"\(iptcNamespaceDecl)\(captureAttrs)>\(subjectBlock)\(descriptionBlock)\(iptcBlock)
            </rdf:Description>
          </rdf:RDF>
        </x:xmpmeta>
        <?xpacket end="r"?>
        """
    }

    nonisolated static func formatNumber(_ value: Double) -> String {
        if value == value.rounded() { return String(Int(value)) }
        return String(format: "%.4g", value)
    }

    /// ISO8601DateFormatter is documented as thread-safe but isn't marked
    /// `Sendable` in the Foundation overlay, so we wrap it in an unchecked
    /// Sendable box. It's used only from `exportXMP` which is itself
    /// `nonisolated static`.
    private static let iso8601Storage: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    nonisolated static var iso8601: ISO8601DateFormatter { iso8601Storage }

    // MARK: - XML escaping (single-pass character scanner)

    nonisolated static func escape(_ value: String) -> String {
        var result = ""
        result.reserveCapacity(value.count + value.count / 10)
        for char in value {
            switch char {
            case "&":  result += "&amp;"
            case "<":  result += "&lt;"
            case ">":  result += "&gt;"
            case "\"": result += "&quot;"
            default:   result.append(char)
            }
        }
        return result
    }

    nonisolated static func unescape(_ value: String) -> String {
        var s = value
        s = s.replacingOccurrences(of: "&lt;",   with: "<")
        s = s.replacingOccurrences(of: "&gt;",   with: ">")
        s = s.replacingOccurrences(of: "&quot;", with: "\"")
        s = s.replacingOccurrences(of: "&apos;", with: "'")
        s = s.replacingOccurrences(of: "&amp;",  with: "&")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Pre-compiled XMP regexes
//
// Every pattern used by `XMPTaggingService` lives here so the regex engine
// is invoked once at type-init instead of on every sidecar read/write.
// Mirrors the pattern already in use by `MetadataReader`.

private enum XMPSchema {
    enum Regex {
        // dc:subject — three flavors depending on whether we want the inner
        // content, the whole element, or the element plus trailing newline.
        static let subjectContent = try! NSRegularExpression(
            pattern: #"(?i)<dc:subject[^>]*>(.*?)</dc:subject>"#,
            options: [.dotMatchesLineSeparators]
        )
        static let subjectFull = try! NSRegularExpression(
            pattern: #"(?i)<dc:subject[^>]*>.*?</dc:subject>"#,
            options: [.dotMatchesLineSeparators]
        )
        static let subjectRemove = try! NSRegularExpression(
            pattern: #"(?i)<dc:subject[^>]*>.*?</dc:subject>\n?"#,
            options: [.dotMatchesLineSeparators]
        )

        // rdf:li items inside a dc:subject block.
        static let liItem = try! NSRegularExpression(
            pattern: #"<rdf:li[^>]*>(.*?)</rdf:li>"#,
            options: [.dotMatchesLineSeparators]
        )

        // <rdf:Description ...> opening tag (capture group 1).
        static let descriptionTag = try! NSRegularExpression(
            pattern: #"(?i)(<rdf:Description\b[^>]*>)"#,
            options: []
        )
        // </rdf:Description> closing tag.
        static let rdfDescriptionClose = try! NSRegularExpression(
            pattern: #"(?i)</rdf:Description>"#,
            options: []
        )

        // dc:description — both the body form and self-closing.
        static let descriptionBody = try! NSRegularExpression(
            pattern: #"(?is)<dc:description\b[^>]*>(.*?)</dc:description>"#,
            options: []
        )
        static let descriptionSelfClosing = try! NSRegularExpression(
            pattern: #"(?is)<dc:description\b[^>]*\s*/>"#,
            options: []
        )

        // Rating and pick — attribute form (xmp:Rating="5") and tag form
        // (<xmp:Rating>5</xmp:Rating>).
        static let ratingAttr = try! NSRegularExpression(
            pattern: #"\b(?:xmp:)?Rating\s*=\s*["']([0-5])["']"#,
            options: []
        )
        static let ratingTag = try! NSRegularExpression(
            pattern: #"<(?:xmp:)?Rating\b[^>]*>([0-5])</(?:xmp:)?Rating>"#,
            options: []
        )
        static let pickAttr = try! NSRegularExpression(
            pattern: #"\bxmpDM:pick\s*=\s*["'](-?[0-1])["']"#,
            options: []
        )
        static let pickTag = try! NSRegularExpression(
            pattern: #"<xmpDM:pick\b[^>]*>(-?[0-1])</xmpDM:pick>"#,
            options: []
        )

        // IPTC element blocks for upsert.
        static let dcCreator = try! NSRegularExpression(
            pattern: #"(?is)<dc:creator\b[^>]*>.*?</dc:creator>"#,
            options: [.dotMatchesLineSeparators]
        )
        static let dcRights = try! NSRegularExpression(
            pattern: #"(?is)<dc:rights\b[^>]*>.*?</dc:rights>"#,
            options: [.dotMatchesLineSeparators]
        )
        static let iptcEmail = try! NSRegularExpression(
            pattern: #"(?is)<Iptc4xmpCore:CiEmailWork\b[^>]*>.*?</Iptc4xmpCore:CiEmailWork>"#,
            options: [.dotMatchesLineSeparators]
        )
        static let iptcPhone = try! NSRegularExpression(
            pattern: #"(?is)<Iptc4xmpCore:CiTelWork\b[^>]*>.*?</Iptc4xmpCore:CiTelWork>"#,
            options: [.dotMatchesLineSeparators]
        )
        static let iptcWebsite = try! NSRegularExpression(
            pattern: #"(?is)<Iptc4xmpCore:CiUrlWork\b[^>]*>.*?</Iptc4xmpCore:CiUrlWork>"#,
            options: [.dotMatchesLineSeparators]
        )
        static let usageTerms = try! NSRegularExpression(
            pattern: #"(?is)<xmpRights:UsageTerms\b[^>]*>.*?</xmpRights:UsageTerms>"#,
            options: [.dotMatchesLineSeparators]
        )
    }
}

// Re-export the pre-compiled regexes at the XMPTaggingService namespace so
// the static helpers can use them without depending on the private `XMPSchema`
// enum directly.
extension XMPTaggingService {
    fileprivate typealias Regex = XMPSchema.Regex
}

private extension String {
    /// Returns nil when the string is empty after trimming, otherwise
    /// returns the trimmed value. Used to drop blank IPTC preference
    /// fields when building an `IPTCMetadata` for export.
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
