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
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else {
            return MetadataSnapshot()
        }

        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any]

        let cameraModel = tiff?[kCGImagePropertyTIFFModel] as? String
        let lensModel = exif?[kCGImagePropertyExifLensModel] as? String
        let captureDateString = exif?[kCGImagePropertyExifDateTimeOriginal] as? String
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
        if let iptc = properties[kCGImagePropertyIPTCDictionary] as? [CFString: Any] {
            rating = iptc[kCGImagePropertyIPTCStarRating] as? Int
        }
        if let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil),
           let xmpData = CGImageMetadataCreateXMPData(metadata, nil) as Data?,
           let xmpString = String(data: xmpData, encoding: .utf8) {

            if rating == nil {
                if let match = Self.ratingAttrRegex.firstMatch(in: xmpString, options: [], range: NSRange(xmpString.startIndex..., in: xmpString)),
                   let range = Range(match.range(at: 1), in: xmpString),
                   let val = Int(xmpString[range]) {
                    rating = val
                } else if let match = Self.ratingTagRegex.firstMatch(in: xmpString, options: [], range: NSRange(xmpString.startIndex..., in: xmpString)),
                          let range = Range(match.range(at: 1), in: xmpString),
                          let val = Int(xmpString[range]) {
                    rating = val
                }
            }

            if let match = Self.pickAttrRegex.firstMatch(in: xmpString, options: [], range: NSRange(xmpString.startIndex..., in: xmpString)),
               let range = Range(match.range(at: 1), in: xmpString),
               let val = Int(xmpString[range]) {
                pick = val
            } else if let match = Self.pickTagRegex.firstMatch(in: xmpString, options: [], range: NSRange(xmpString.startIndex..., in: xmpString)),
                      let range = Range(match.range(at: 1), in: xmpString),
                      let val = Int(xmpString[range]) {
                pick = val
            }
        }

        return MetadataSnapshot(
            cameraModel: cameraModel,
            lensModel: lensModel,
            captureDate: captureDateString.flatMap(Self.parseExifDate),
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
        guard string.count >= 19 else { return nil }
        let chars = Array(string.prefix(19))
        guard chars[4] == ":", chars[7] == ":", chars[10] == " ", chars[13] == ":", chars[16] == ":" else {
            return nil
        }
        guard let year = Int(String(chars[0...3])),
              let month = Int(String(chars[5...6])),
              let day = Int(String(chars[8...9])),
              let hour = Int(String(chars[11...12])),
              let minute = Int(String(chars[14...15])),
              let second = Int(String(chars[17...18]))
        else {
            return nil
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
}


