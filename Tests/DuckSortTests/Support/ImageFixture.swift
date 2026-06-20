import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

enum TempDir {
    static func make() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DuckSortTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

enum ImageFixture {
    static func writeJPEG(to url: URL, cameraModel: String, lensModel: String, iso: Int) throws {
        let width = 1, height = 1
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = ctx.makeImage() else {
            throw NSError(domain: "ImageFixture", code: 1)
        }

        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.jpeg.identifier as CFString, 1, nil
        ) else {
            throw NSError(domain: "ImageFixture", code: 2)
        }

        let properties: [CFString: Any] = [
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFModel: cameraModel
            ],
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifLensModel: lensModel,
                kCGImagePropertyExifISOSpeedRatings: [iso]
            ]
        ]
        CGImageDestinationAddImage(dest, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw NSError(domain: "ImageFixture", code: 3)
        }
    }
}
