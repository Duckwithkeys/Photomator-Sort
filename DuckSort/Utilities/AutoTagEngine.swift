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

    /// Evaluates all enabled rules against the given metadata snapshot and
    /// returns matching suggestions deduplicated by tag name.
    ///
    /// - Parameters:
    ///   - metadata: The photo's EXIF metadata snapshot.
    ///   - rules: The set of enabled rules to evaluate.
    ///   - resolvedCategories: Pre-resolved category name → UUID mapping
    ///     (caller resolves on the main actor; avoids @MainActor isolation
    ///     violation from this Sendable engine).
    /// - Returns: A deduplicated array of suggestions.
    func suggestions(
        from metadata: MetadataSnapshot,
        rules: [AutoTagRule],
        resolvedCategories: [String: UUID?]
    ) -> [AutoTagSuggestion] {
        // If metadata is empty (no EXIF), return immediately.
        guard metadata.hasAnyField else { return [] }

        var suggestions: [AutoTagSuggestion] = []
        var seenTagNames = Set<String>()  // for deduplication (case-insensitive)

        for rule in rules where rule.enabled {
            guard rule.condition.matches(metadata) else { continue }

            for suggestedTag in rule.suggestedTags {
                // Deduplicate: skip if we already have a suggestion for this
                // tag name (case-insensitive) targeting the same category.
                let dedupKey = (suggestedTag.name.lowercased(), rule.confidence)
                if seenTagNames.contains(dedupKey.0) { continue }
                seenTagNames.insert(dedupKey.0)

                // Resolve category name → UUID via pre-resolved map.
                let resolvedCategoryID = suggestedTag.category.flatMap {
                    resolvedCategories[$0]
                } ?? nil

                // Build the reason string.
                let reason = buildReason(rule.condition, metadata)

                let suggestion = AutoTagSuggestion(
                    tagName: suggestedTag.name,
                    reason: reason,
                    categoryID: resolvedCategoryID,
                    confidence: rule.confidence
                )

                suggestions.append(suggestion)
            }
        }

        return suggestions
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
