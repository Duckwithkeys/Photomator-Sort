//
//  MetadataReader.swift
//  PhotomatorSort
//

import Foundation
import ImageIO

struct MetadataReader: Sendable {
    private static let ratingAttrRegex = try! NSRegularExpression(pattern: #"\b(?:xmp:)?Rating\s*=\s*["']([0-5])["']"#, options: [])
    private static let ratingTagRegex = try! NSRegularExpression(pattern: #"<(?:xmp:)?Rating\b[^>]*>([0-5])</(?:xmp:)?Rating>"#, options: [])
    private static let pickAttrRegex = try! NSRegularExpression(pattern: #"\bxmpDM:pick\s*=\s*["'](-?[0-1])["']"#, options: [])
    private static let pickTagRegex = try! NSRegularExpression(pattern: #"<xmpDM:pick\b[^>]*>(-?[0-1])</xmpDM:pick>"#, options: [])

    func metadata(for url: URL) -> MetadataSnapshot {
        if url.pathExtension.lowercased() == "xmp" {
            if let data = try? Data(contentsOf: url), let xmlString = String(data: data, encoding: .utf8) {
                return parseXMPText(xmlString)
            }
        }

        let options: [CFString: Any] = [kCGImageSourceShouldCache as CFString: false]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else {
            if let data = try? Data(contentsOf: url), let xmlString = String(data: data, encoding: .utf8) {
                return parseXMPText(xmlString)
            }
            // File system fallback for missing source
            var snapshot = MetadataSnapshot()
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let fileCreationDate = attrs[.creationDate] as? Date {
                snapshot.captureDate = fileCreationDate
            }
            return snapshot
        }

        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any]
        let iptc = properties[kCGImagePropertyIPTCDictionary] as? [CFString: Any]

        let cameraModel = tiff?[kCGImagePropertyTIFFModel] as? String
        let lensModel = exif?[kCGImagePropertyExifLensModel] as? String
        
        // Exif datetime -> TIFF datetime -> IPTC datetime
        var captureDateString = exif?[kCGImagePropertyExifDateTimeOriginal] as? String
            ?? tiff?[kCGImagePropertyTIFFDateTime] as? String
        
        if captureDateString == nil, let iptc = iptc {
            if let dateStr = iptc[kCGImagePropertyIPTCDateCreated] as? String {
                if let timeStr = iptc[kCGImagePropertyIPTCTimeCreated] as? String {
                    captureDateString = "\(dateStr) \(timeStr)"
                } else {
                    captureDateString = dateStr
                }
            }
        }
        
        var captureDate = captureDateString.flatMap(Self.parseExifDate)
        
        let aperture = exif?[kCGImagePropertyExifFNumber] as? Double
        let shutterSpeed = exif?[kCGImagePropertyExifExposureTime] as? Double
        let isoArray = exif?[kCGImagePropertyExifISOSpeedRatings] as? [Int]

        // Advanced fields
        let focalLength = exif?[kCGImagePropertyExifFocalLength] as? Double
        let focalLengthIn35mm = exif?[kCGImagePropertyExifFocalLenIn35mmFilm] as? Double
        let whiteBalanceRaw = exif?[kCGImagePropertyExifWhiteBalance] as? Int
        let flashRaw = exif?[kCGImagePropertyExifFlash] as? Int
        let exposureProgramRaw = exif?[kCGImagePropertyExifExposureProgram] as? Int
        let meteringModeRaw = exif?[kCGImagePropertyExifMeteringMode] as? Int
        let exposureBias = exif?[kCGImagePropertyExifExposureBiasValue] as? Double

        let pixelWidth = properties[kCGImagePropertyPixelWidth] as? Int
        let pixelHeight = properties[kCGImagePropertyPixelHeight] as? Int
        let orientation = properties[kCGImagePropertyOrientation] as? Int
        let colorSpaceRaw = properties[kCGImagePropertyColorModel] as? String
        let profileName = properties[kCGImagePropertyProfileName] as? String

        let gpsLatitude = gps?[kCGImagePropertyGPSLatitude] as? Double
        let gpsLongitude = gps?[kCGImagePropertyGPSLongitude] as? Double
        let gpsAltitude = gps?[kCGImagePropertyGPSAltitude] as? Double

        var rating: Int? = nil
        var pick: Int? = nil
        if let iptc = iptc {
            rating = iptc[kCGImagePropertyIPTCStarRating] as? Int
        }
        
        // Check embedded XMP
        if let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil),
           let xmpData = CGImageMetadataCreateXMPData(metadata, nil) as Data?,
           let xmpString = String(data: xmpData, encoding: .utf8) {

            let xmpSnapshot = parseXMPText(xmpString)
            if rating == nil {
                rating = xmpSnapshot.rating
            }
            if pick == nil {
                pick = xmpSnapshot.pick
            }
            if captureDate == nil {
                captureDate = xmpSnapshot.captureDate
            }
        }
        
        // Final File System Fallback
        if captureDate == nil {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let fileCreationDate = attrs[.creationDate] as? Date {
                captureDate = fileCreationDate
            }
        }

        return MetadataSnapshot(
            cameraModel: cameraModel,
            lensModel: lensModel,
            captureDate: captureDate,
            aperture: aperture,
            shutterSpeed: shutterSpeed,
            iso: isoArray?.first,
            rating: rating,
            pick: pick,
            focalLength: focalLength,
            focalLengthIn35mm: focalLengthIn35mm,
            whiteBalance: Self.whiteBalanceLabel(whiteBalanceRaw),
            flashFired: Self.flashFired(flashRaw),
            flashMode: Self.flashModeLabel(flashRaw),
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            orientation: orientation,
            colorSpace: Self.colorSpaceLabel(colorSpaceRaw),
            colorProfile: profileName,
            gpsLatitude: gpsLatitude,
            gpsLongitude: gpsLongitude,
            gpsAltitude: gpsAltitude,
            exposureProgram: Self.exposureProgramLabel(exposureProgramRaw),
            meteringMode: Self.meteringModeLabel(meteringModeRaw),
            exposureBias: exposureBias
        )
    }

    private static func whiteBalanceLabel(_ raw: Int?) -> String? {
        guard let raw else { return nil }
        switch raw {
        case 0: return "Auto"
        case 1: return "Manual"
        default: return "Unknown (\(raw))"
        }
    }

    private static func flashFired(_ raw: Int?) -> Bool? {
        guard let raw else { return nil }
        // Bit 0 indicates whether the flash fired.
        return (raw & 0x1) == 0x1
    }

    private static func flashModeLabel(_ raw: Int?) -> String? {
        guard let raw else { return nil }
        switch raw & 0x18 {
        case 0x00: return "Off"
        case 0x08: return "On"
        case 0x10: return "Auto"
        default:   return "Unknown"
        }
    }

    private static func exposureProgramLabel(_ raw: Int?) -> String? {
        guard let raw else { return nil }
        switch raw {
        case 0: return "Not defined"
        case 1: return "Manual"
        case 2: return "Program AE"
        case 3: return "Aperture-priority AE"
        case 4: return "Shutter speed priority AE"
        case 5: return "Creative (Slow speed)"
        case 6: return "Action (High speed)"
        case 7: return "Portrait"
        case 8: return "Landscape"
        default: return "Unknown (\(raw))"
        }
    }

    private static func meteringModeLabel(_ raw: Int?) -> String? {
        guard let raw else { return nil }
        switch raw {
        case 0: return "Unknown"
        case 1: return "Average"
        case 2: return "Center-weighted average"
        case 3: return "Spot"
        case 4: return "Multi-spot"
        case 5: return "Pattern"
        case 6: return "Partial"
        default: return "Other (\(raw))"
        }
    }

    private static func colorSpaceLabel(_ raw: String?) -> String? {
        guard let raw else { return nil }
        switch raw {
        case String(kCGImagePropertyColorModelRGB): return "sRGB / RGB"
        case String(kCGImagePropertyColorModelGray): return "Grayscale"
        case String(kCGImagePropertyColorModelCMYK): return "CMYK"
        case String(kCGImagePropertyColorModelLab): return "Lab"
        default: return raw
        }
    }

    static func parseExifDate(_ string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 10 else { return nil }

        // Attempt 1: ISO8601 formatting (with/without fractional seconds or offsets)
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatter.date(from: trimmed) {
            return date
        }
        
        isoFormatter.formatOptions = [.withInternetDateTime]
        if let date = isoFormatter.date(from: trimmed) {
            return date
        }

        // Attempt 2: Direct numeric separator scanning (safely handles YYYY:MM:DD, YYYY-MM-DD, YYYY/MM/DD)
        let chars = Array(trimmed)
        guard let year = Int(String(chars[0...3])),
              let month = Int(String(chars[5...6])),
              let day = Int(String(chars[8...9]))
        else {
            return nil
        }

        var hour = 0
        var minute = 0
        var second = 0

        if chars.count >= 19 {
            if let h = Int(String(chars[11...12])),
               let m = Int(String(chars[14...15])),
               let s = Int(String(chars[17...18])) {
                hour = h
                minute = m
                second = s
            }
        }

        var dateComponents = DateComponents()
        dateComponents.year = year
        dateComponents.month = month
        dateComponents.day = day
        dateComponents.hour = hour
        dateComponents.minute = minute
        dateComponents.second = second

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(from: dateComponents)
    }

    private func parseXMPText(_ xml: String) -> MetadataSnapshot {
        func extractValue(forKeys keys: [String]) -> String? {
            for key in keys {
                // Check attribute: key="val" or key='val'
                let attrPattern = #"\b"# + NSRegularExpression.escapedPattern(for: key) + #"\s*=\s*["']([^"']+)["']"#
                if let regex = try? NSRegularExpression(pattern: attrPattern, options: []),
                   let match = regex.firstMatch(in: xml, options: [], range: NSRange(xml.startIndex..., in: xml)),
                   let range = Range(match.range(at: 1), in: xml) {
                    return String(xml[range])
                }
                // Check tag: <key>val</key>
                let tagPattern = #"<"# + NSRegularExpression.escapedPattern(for: key) + #"\b[^>]*>([^<]+)</"# + NSRegularExpression.escapedPattern(for: key) + #">"#
                if let regex = try? NSRegularExpression(pattern: tagPattern, options: []),
                   let match = regex.firstMatch(in: xml, options: [], range: NSRange(xml.startIndex..., in: xml)),
                   let range = Range(match.range(at: 1), in: xml) {
                    return String(xml[range])
                }
            }
            return nil
        }

        func extractSeqValue(forKey key: String) -> String? {
            let seqPattern = #"<"# + NSRegularExpression.escapedPattern(for: key) + #"\b[^>]*>.*?<rdf:li[^>]*>([^<]+)</rdf:li>.*?</"# + NSRegularExpression.escapedPattern(for: key) + #">"#
            if let regex = try? NSRegularExpression(pattern: seqPattern, options: [.dotMatchesLineSeparators]),
               let match = regex.firstMatch(in: xml, options: [], range: NSRange(xml.startIndex..., in: xml)),
               let range = Range(match.range(at: 1), in: xml) {
                return String(xml[range])
            }
            return nil
        }

        // 1. Camera Model
        let make = extractValue(forKeys: ["tiff:Make", "Make"])
        let model = extractValue(forKeys: ["tiff:Model", "Model"])
        var cameraModel: String? = nil
        if let make, let model {
            cameraModel = model.lowercased().contains(make.lowercased()) ? model : "\(make) \(model)"
        } else {
            cameraModel = model ?? make
        }

        // 2. Lens Model
        let lensModel = extractValue(forKeys: ["exifEX:LensModel", "exif:LensModel", "aux:Lens", "LensModel", "Lens"])

        // 3. Focal Length in 35mm
        var focalLengthIn35mm: Double? = nil
        if let flStr = extractValue(forKeys: ["exif:FocalLengthIn35mmFilm", "exifEX:FocalLengthIn35mmFilm", "FocalLengthIn35mmFilm"]) {
            focalLengthIn35mm = Double(flStr)
        } else if let flStr = extractValue(forKeys: ["exif:FocalLength", "FocalLength"]) {
            if flStr.contains("/") {
                let parts = flStr.components(separatedBy: "/")
                if parts.count == 2, let num = Double(parts[0]), let den = Double(parts[1]), den > 0 {
                    focalLengthIn35mm = num / den
                }
            } else {
                focalLengthIn35mm = Double(flStr)
            }
        }

        // 4. ISO
        var iso: Int? = nil
        if let isoStr = extractSeqValue(forKey: "exif:ISOSpeedRatings") ?? extractValue(forKeys: ["exif:ISOSpeedRatings", "exif:RecommendedExposureIndex", "exifEX:RecommendedExposureIndex", "ISOSpeedRatings"]) {
            iso = Int(isoStr)
        }

        // 5. Aperture
        var aperture: Double? = nil
        if let apStr = extractValue(forKeys: ["exif:FNumber", "exif:ApertureValue", "FNumber"]) {
            if apStr.contains("/") {
                let parts = apStr.components(separatedBy: "/")
                if parts.count == 2, let num = Double(parts[0]), let den = Double(parts[1]), den > 0 {
                    aperture = num / den
                }
            } else {
                aperture = Double(apStr)
            }
        }

        // 6. Flash Fired
        var flashFired: Bool? = nil
        if let flashStr = extractValue(forKeys: ["exif:Fired", "stEvt:action", "Fired"]) {
            flashFired = flashStr.lowercased() == "true" || flashStr == "1"
        } else if let flashRawStr = extractValue(forKeys: ["exif:Flash", "Flash"]) {
            if let rawInt = Int(flashRawStr) {
                flashFired = (rawInt & 0x1) == 0x1
            } else {
                flashFired = flashRawStr.lowercased().contains("true") || flashRawStr.lowercased().contains("fired")
            }
        }

        // 7. Width and Height
        var width: Int? = nil
        var height: Int? = nil
        if let wStr = extractValue(forKeys: ["tiff:ImageWidth", "exif:PixelXDimension", "ImageWidth"]) { width = Int(wStr) }
        if let hStr = extractValue(forKeys: ["tiff:ImageLength", "exif:PixelYDimension", "ImageLength"]) { height = Int(hStr) }

        // 8. Date created
        var captureDate: Date? = nil
        if let dateStr = extractValue(forKeys: ["exif:DateTimeOriginal", "xmp:CreateDate", "photoshop:DateCreated", "CreateDate", "DateTimeOriginal"]) {
            captureDate = Self.parseExifDate(dateStr)
        }

        // 9. Star Rating
        var rating: Int? = nil
        if let match = Self.ratingAttrRegex.firstMatch(in: xml, options: [], range: NSRange(xml.startIndex..., in: xml)),
           let range = Range(match.range(at: 1), in: xml),
           let val = Int(xml[range]) {
            rating = val
        } else if let match = Self.ratingTagRegex.firstMatch(in: xml, options: [], range: NSRange(xml.startIndex..., in: xml)),
                  let range = Range(match.range(at: 1), in: xml),
                  let val = Int(xml[range]) {
            rating = val
        }

        // 10. Pick/Reject Flags
        var pick: Int? = nil
        if let match = Self.pickAttrRegex.firstMatch(in: xml, options: [], range: NSRange(xml.startIndex..., in: xml)),
           let range = Range(match.range(at: 1), in: xml),
           let val = Int(xml[range]) {
            pick = val
        } else if let match = Self.pickTagRegex.firstMatch(in: xml, options: [], range: NSRange(xml.startIndex..., in: xml)),
                  let range = Range(match.range(at: 1), in: xml),
                  let val = Int(xml[range]) {
            pick = val
        }

        return MetadataSnapshot(
            cameraModel: cameraModel,
            lensModel: lensModel,
            captureDate: captureDate,
            aperture: aperture,
            shutterSpeed: nil,
            iso: iso,
            rating: rating,
            pick: pick,
            focalLength: nil,
            focalLengthIn35mm: focalLengthIn35mm,
            whiteBalance: nil,
            flashFired: flashFired,
            flashMode: nil,
            pixelWidth: width,
            pixelHeight: height,
            orientation: nil,
            colorSpace: nil,
            colorProfile: nil,
            gpsLatitude: nil,
            gpsLongitude: nil,
            gpsAltitude: nil,
            exposureProgram: nil,
            meteringMode: nil,
            exposureBias: nil
        )
    }
}


