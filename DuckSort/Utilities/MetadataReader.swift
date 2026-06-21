//
//  MetadataReader.swift
//  PhotomatorSort
//

import Foundation
import ImageIO

struct MetadataReader: Sendable {
    func metadata(for url: URL) -> MetadataSnapshot {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else {
            return MetadataSnapshot()
        }

        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]

        let cameraModel = tiff?[kCGImagePropertyTIFFModel] as? String
        let lensModel = exif?[kCGImagePropertyExifLensModel] as? String
        let captureDateString = exif?[kCGImagePropertyExifDateTimeOriginal] as? String
        let aperture = exif?[kCGImagePropertyExifFNumber] as? Double
        let shutterSpeed = exif?[kCGImagePropertyExifExposureTime] as? Double
        let isoArray = exif?[kCGImagePropertyExifISOSpeedRatings] as? [Int]

        var rating: Int? = nil
        var pick: Int? = nil
        if let iptc = properties[kCGImagePropertyIPTCDictionary] as? [CFString: Any] {
            rating = iptc[kCGImagePropertyIPTCStarRating] as? Int
        }
        if let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil),
           let xmpData = CGImageMetadataCreateXMPData(metadata, nil) as Data?,
           let xmpString = String(data: xmpData, encoding: .utf8) {
            
            if rating == nil {
                let attrPattern = #"\b(?:xmp:)?Rating\s*=\s*["']([0-5])["']"#
                if let regex = try? NSRegularExpression(pattern: attrPattern, options: []),
                   let match = regex.firstMatch(in: xmpString, options: [], range: NSRange(xmpString.startIndex..., in: xmpString)),
                   let range = Range(match.range(at: 1), in: xmpString),
                   let val = Int(xmpString[range]) {
                    rating = val
                } else {
                    let tagPattern = #"<(?:xmp:)?Rating\b[^>]*>([0-5])</(?:xmp:)?Rating>"#
                    if let regex = try? NSRegularExpression(pattern: tagPattern, options: []),
                       let match = regex.firstMatch(in: xmpString, options: [], range: NSRange(xmpString.startIndex..., in: xmpString)),
                       let range = Range(match.range(at: 1), in: xmpString),
                       let val = Int(xmpString[range]) {
                        rating = val
                    }
                }
            }
            
            let pickAttrPattern = #"\bxmpDM:pick\s*=\s*["'](-?[0-1])["']"#
            if let regex = try? NSRegularExpression(pattern: pickAttrPattern, options: []),
               let match = regex.firstMatch(in: xmpString, options: [], range: NSRange(xmpString.startIndex..., in: xmpString)),
               let range = Range(match.range(at: 1), in: xmpString),
               let val = Int(xmpString[range]) {
                pick = val
            } else {
                let pickTagPattern = #"<xmpDM:pick\b[^>]*>(-?[0-1])</xmpDM:pick>"#
                if let regex = try? NSRegularExpression(pattern: pickTagPattern, options: []),
                   let match = regex.firstMatch(in: xmpString, options: [], range: NSRange(xmpString.startIndex..., in: xmpString)),
                   let range = Range(match.range(at: 1), in: xmpString),
                   let val = Int(xmpString[range]) {
                    pick = val
                }
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
            pick: pick
        )
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


