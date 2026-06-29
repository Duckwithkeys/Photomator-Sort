//
//  VisionEngineActor.swift
//  DuckSort
//
//  On-device AI classification engine using Apple's Vision framework.
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

    private init() {}

    /// Classifies the content of an image file asynchronously.
    func classifyImage(at url: URL, confidenceThreshold: Float = 0.3) async throws -> [VisionClassificationResult] {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else { return [] }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 512,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
            return []
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNClassifyImageRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let observations = request.results as? [VNClassificationObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                let results = observations
                    .filter { $0.confidence >= confidenceThreshold }
                    .map { VisionClassificationResult(identifier: $0.identifier, confidence: $0.confidence) }
                continuation.resume(returning: results)
            }

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Detects human body poses within an image file.
    func detectBodyPoses(at url: URL) async throws -> Int {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else { return 0 }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 1024,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
            return 0
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNDetectHumanBodyPoseRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                let count = request.results?.count ?? 0
                continuation.resume(returning: count)
            }

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
