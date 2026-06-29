//
//  VisionEngineActor.swift
//  DuckSort
//
//  On-device AI classification engine using Apple's Vision framework and Neural Engine.
//  Performs scene, object, landscape, and pet detection off the main thread.
//

import Foundation
import Vision
import AppKit

@globalActor
actor VisionActor {
    static let shared = VisionActor()
}

struct VisionClassificationResult: Sendable, Identifiable {
    var id: String { identifier }
    let identifier: String
    let confidence: Float
}

@VisionActor
final class VisionEngineActor {
    static let shared = VisionEngineActor()

    private let cache = NSCache<NSURL, NSArray>()

    private init() {
        cache.countLimit = 500
    }

    /// Classifies the content of an image file asynchronously with Neural Engine acceleration.
    func classifyImage(at url: URL, confidenceThreshold: Float = 0.3) async throws -> [VisionClassificationResult] {
        let nsURL = url.standardizedFileURL as NSURL
        if let cached = cache.object(forKey: nsURL) as? [VisionClassificationResult] {
            return cached.filter { $0.confidence >= confidenceThreshold }
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 299,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCache: false
        ]

        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
            return []
        }

        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        guard let observations = request.results else {
            return []
        }

        let results = observations.map { VisionClassificationResult(identifier: $0.identifier, confidence: $0.confidence) }
        cache.setObject(results as NSArray, forKey: nsURL)

        return results.filter { $0.confidence >= confidenceThreshold }
    }

    /// Detects human body poses within an image file.
    func detectBodyPoses(at url: URL) async throws -> Int {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 1024,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCache: false
        ]
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
            return 0
        }

        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        return request.results?.count ?? 0
    }
}
