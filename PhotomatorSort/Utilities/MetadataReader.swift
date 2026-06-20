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

        return MetadataSnapshot(
            cameraModel: cameraModel,
            lensModel: lensModel,
            captureDate: captureDateString.flatMap(Self.parseExifDate),
            aperture: aperture,
            shutterSpeed: shutterSpeed,
            iso: isoArray?.first
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


