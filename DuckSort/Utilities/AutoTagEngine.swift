//
//  AutoTagEngine.swift
//  DuckSort
//
//  Pure evaluation engine: takes a MetadataSnapshot and a set of enabled
//  AutoTagRule instances, returns matching AutoTagSuggestion arrays.
//  No I/O, fast, called on-demand when a photo is focused in the large
//  viewer.
//

import Foundation

final class AutoTagEngine: Sendable {
    static let shared = AutoTagEngine()

    /// EXIF auto-tagging has been deprecated in favor of on-device AI Vision ML.
    func suggestions(
        from metadata: MetadataSnapshot,
        rules: [AutoTagRule],
        resolvedCategories: [String: UUID?]
    ) -> [AutoTagSuggestion] {
        return []
    }

    /// Evaluates Vision ML scene classifications for a photo URL and converts them to AutoTagSuggestions.
    func visionSuggestions(for url: URL, confidenceThreshold: Float = 0.3) async -> [AutoTagSuggestion] {
        guard let classifications = try? await VisionEngineActor.shared.classifyImage(at: url, confidenceThreshold: confidenceThreshold) else {
            return []
        }

        return classifications.map { classification in
            let label = classification.identifier.components(separatedBy: ",").first?.capitalized ?? classification.identifier
            let confidenceEnum: Confidence = classification.confidence >= 0.7 ? .high : (classification.confidence >= 0.4 ? .medium : .low)
            return AutoTagSuggestion(
                tagName: label,
                reason: "Vision ML: \(Int(classification.confidence * 100))% match",
                categoryID: nil,
                confidence: confidenceEnum,
                source: .visionML
            )
        }
    }

    // MARK: - Private

    private func buildReason(_ condition: Condition, _ metadata: MetadataSnapshot) -> String {
        switch condition {
        case .cameraBrand, .cameraBrandValue:
            return "Camera: \(metadata.cameraModel ?? "—")"
        case .focalLength35mmLess, .focalLength35mmMore, .focalLength35mmValue:
            if let eq35 = metadata.focalLengthIn35mm {
                return "35mm eq. \(String(format: "%.0f", eq35))mm"
            }
            return "35mm eq. unknown"
        case .isoLess, .isoMore, .isoValue:
            return "ISO \(metadata.iso ?? 0)"
        case .apertureLess, .apertureMore, .apertureValue:
            if let ap = metadata.aperture {
                return "f/\(String(format: "%.1f", ap))"
            }
            return "Aperture unknown"
        case .flashFired:
            return "Flash: Fired"
        case .flashNotFired:
            return "Flash: Did not fire"
        case .aspectRatio, .aspectRatioValue:
            guard let w = metadata.pixelWidth, let h = metadata.pixelHeight else {
                return "Dimensions unknown"
            }
            return "\(w) × \(h)"
        case .imageStabilization:
            return "Image stabilization detected"
        case .lensType, .lensTypeValue:
            return "Lens: \(metadata.lensModel ?? "—")"
        case .lensTypeNot, .lensTypeNotValue:
            return "Lens: \(metadata.lensModel ?? "—") (does not match exclusion)"
        }
    }
}



// MARK: - MetadataSnapshot helper

extension MetadataSnapshot {
    /// Returns `true` if any EXIF field is populated.
    var hasAnyField: Bool {
        cameraModel != nil
        || lensModel != nil
        || captureDate != nil
        || aperture != nil
        || shutterSpeed != nil
        || iso != nil
        || rating != nil
        || pick != nil
        || focalLength != nil
        || focalLengthIn35mm != nil
        || whiteBalance != nil
        || flashFired != nil
        || flashMode != nil
        || pixelWidth != nil
        || pixelHeight != nil
        || orientation != nil
        || colorSpace != nil
        || colorProfile != nil
        || gpsLatitude != nil
        || gpsLongitude != nil
        || gpsAltitude != nil
        || exposureProgram != nil
        || meteringMode != nil
        || exposureBias != nil
        || caption != nil
    }
}
