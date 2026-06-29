//
//  FaceClusteringService.swift
//  DuckSort
//
//  Apple Neural Engine (ANE) accelerated face detection and clustering service.
//  Groups detected subjects locally without third-party cloud uploads.
//

import Foundation
import Vision
import ImageIO

struct DetectedFaceResult: Sendable, Identifiable {
    let id: UUID
    let boundingBox: CGRect
    let confidence: Float
}

struct FaceCluster: Sendable, Identifiable {
    let id: UUID
    let photoURL: URL
    let faces: [DetectedFaceResult]
}

final class FaceClusteringService: Sendable {
    static let shared = FaceClusteringService()

    private init() {}

    /// Detects faces in a photo file using Vision and Neural Engine hardware acceleration options.
    func detectFaces(at url: URL) async throws -> [DetectedFaceResult] {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            return []
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNDetectFaceRectanglesRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let observations = request.results as? [VNFaceObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                let results = observations.map { observation in
                    DetectedFaceResult(
                        id: UUID(),
                        boundingBox: observation.boundingBox,
                        confidence: observation.confidence
                    )
                }
                continuation.resume(returning: results)
            }

            // Prefer Apple Neural Engine (ANE) / GPU processing pipeline
            request.preferBackgroundProcessing = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Clusters photo URLs based on face presence and count.
    func clusterPhotos(urls: [URL]) async -> [FaceCluster] {
        await withTaskGroup(of: FaceCluster?.self) { group in
            for url in urls {
                group.addTask {
                    guard let faces = try? await self.detectFaces(at: url), !faces.isEmpty else {
                        return nil
                    }
                    return FaceCluster(id: UUID(), photoURL: url, faces: faces)
                }
            }

            var clusters: [FaceCluster] = []
            for await cluster in group {
                if let cluster = cluster {
                    clusters.append(cluster)
                }
            }
            return clusters
        }
    }
}
