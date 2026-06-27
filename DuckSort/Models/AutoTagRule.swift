//
//  AutoTagRule.swift
//  DuckSort
//
//  Data models for the auto-tagging feature. Rules are evaluated against
//  a photo's EXIF metadata when it is focused in the large viewer, and
//  matching suggestions are offered to the user.
//

import Foundation

// MARK: - Suggestion

/// A single tag suggestion produced by the auto-tag engine. Ephemeral —
/// not persisted. Created on every focus of a photo.
struct AutoTagSuggestion: Identifiable, Sendable {
    let id: UUID = UUID()
    let tagName: String           // e.g. "Fuji", "Wide Angle"
    let reason: String            // e.g. "Camera: Fujifilm X-T5" or "35mm eq. 24mm"
    let categoryID: UUID?         // nil = suggest new tag, not = existing category
    let confidence: Confidence    // .high, .medium, .low
}

enum Confidence: String, Codable, Sendable {
    case high
    case medium
    case low
}

// MARK: - Rule

/// A configurable rule that maps EXIF conditions to suggested tags.
struct AutoTagRule: Codable, Sendable {
    let id: UUID
    var name: String              // Display name in settings, e.g. "Camera Brand"
    var enabled: Bool = true      // Toggle on/off
    var condition: Condition
    var suggestedTags: [SuggestedTag]
    var confidence: Confidence    // Stored property allowing user editing

    init(id: UUID, name: String, enabled: Bool = true, condition: Condition, suggestedTags: [SuggestedTag], confidence: Confidence? = nil) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.condition = condition
        self.suggestedTags = suggestedTags
        
        if let confidence {
            self.confidence = confidence
        } else {
            // Default confidence based on condition type (for backwards compatibility/defaults)
            switch condition {
            case .cameraBrand, .cameraBrandValue, .flashFired, .flashNotFired,
                 .lensType, .lensTypeValue, .lensTypeNot, .lensTypeNotValue,
                 .imageStabilization:
                self.confidence = .high
            default:
                self.confidence = .medium
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, name, enabled, condition, suggestedTags, confidence
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        condition = try container.decode(Condition.self, forKey: .condition)
        suggestedTags = try container.decode([SuggestedTag].self, forKey: .suggestedTags)
        
        if let conf = try container.decodeIfPresent(Confidence.self, forKey: .confidence) {
            confidence = conf
        } else {
            // Fallback default assignments
            switch condition {
            case .cameraBrand, .cameraBrandValue, .flashFired, .flashNotFired,
                 .lensType, .lensTypeValue, .lensTypeNot, .lensTypeNotValue,
                 .imageStabilization:
                confidence = .high
            default:
                confidence = .medium
            }
        }
    }

    /// Returns the default set of rules shipped with DuckSort. All enabled.
    static var defaultRules: [AutoTagRule] {
        [
            // Camera Brand detection
            AutoTagRule(
                id: UUID(),
                name: "Camera Brand",
                condition: .cameraBrandValue("Fujifilm"),
                suggestedTags: [.init(name: "Fuji", category: nil)]
            ),

            // Focal Length — Wide Angle
            AutoTagRule(
                id: UUID(),
                name: "Focal Length < 35mm (35mm eq.)",
                condition: .focalLength35mmValue(35.0),
                suggestedTags: [.init(name: "Wide Angle", category: nil)]
            ),

            // Focal Length — Telephoto
            AutoTagRule(
                id: UUID(),
                name: "Focal Length > 200mm (35mm eq.)",
                condition: .focalLength35mmValue(200.0),
                suggestedTags: [.init(name: "Telephoto", category: nil)]
            ),

            // ISO — Low
            AutoTagRule(
                id: UUID(),
                name: "ISO < 200",
                condition: .isoValue(200),
                suggestedTags: [.init(name: "Low ISO", category: nil)]
            ),

            // ISO — High
            AutoTagRule(
                id: UUID(),
                name: "ISO > 3200",
                condition: .isoValue(3200),
                suggestedTags: [.init(name: "High ISO", category: nil)]
            ),

            // Aperture — Shallow Depth of Field
            AutoTagRule(
                id: UUID(),
                name: "Aperture < 2.8",
                condition: .apertureValue(2.8),
                suggestedTags: [.init(name: "Shallow Depth of Field", category: nil)]
            ),

            // Aperture — Deep Depth of Field
            AutoTagRule(
                id: UUID(),
                name: "Aperture > 8.0",
                condition: .apertureValue(8.0),
                suggestedTags: [.init(name: "Deep Depth of Field", category: nil)]
            ),

            // Flash — Fired
            AutoTagRule(
                id: UUID(),
                name: "Flash Fired",
                condition: .flashFired,
                suggestedTags: [.init(name: "Flash", category: nil)]
            ),

            // Flash — Not Fired
            AutoTagRule(
                id: UUID(),
                name: "Flash Did Not Fire",
                condition: .flashNotFired,
                suggestedTags: [.init(name: "Natural Light", category: nil)]
            ),

            // Aspect Ratio — 3:2
            AutoTagRule(
                id: UUID(),
                name: "Aspect Ratio 3:2",
                condition: .aspectRatioValue(1.5),
                suggestedTags: [.init(name: "3:2", category: nil)]
            ),

            // Aspect Ratio — 16:9
            AutoTagRule(
                id: UUID(),
                name: "Aspect Ratio 16:9",
                condition: .aspectRatioValue(1.78),
                suggestedTags: [.init(name: "16:9", category: nil)]
            ),

            // Lens — Macro
            AutoTagRule(
                id: UUID(),
                name: "Lens Contains 'Macro'",
                condition: .lensTypeValue("Macro"),
                suggestedTags: [.init(name: "Macro", category: nil)]
            ),

            // Lens — Telephoto
            AutoTagRule(
                id: UUID(),
                name: "Lens Contains 'Tele'",
                condition: .lensTypeValue("Tele"),
                suggestedTags: [.init(name: "Telephoto", category: nil)]
            ),

            // Lens — Wide
            AutoTagRule(
                id: UUID(),
                name: "Lens Contains 'Wide'",
                condition: .lensTypeValue("Wide"),
                suggestedTags: [.init(name: "Wide Angle", category: nil)]
            ),
        ]
    }
}

// MARK: - Condition

enum Condition: Codable, Sendable {
    // Discriminator cases (no associated values).
    case cameraBrand
    case focalLength35mmLess
    case focalLength35mmMore
    case isoLess
    case isoMore
    case apertureLess
    case apertureMore
    case flashFired
    case flashNotFired
    case aspectRatio
    case imageStabilization
    case lensType
    case lensTypeNot

    // Value cases (unlabeled associated values — Swift 6 compatibility).
    case cameraBrandValue(String)
    case focalLength35mmValue(Double)
    case isoValue(Int)
    case apertureValue(Double)
    case aspectRatioValue(Double)
    case lensTypeValue(String)
    case lensTypeNotValue(String)

    // MARK: - Matching

    /// Returns `true` if the condition matches the given metadata snapshot.
    func matches(_ metadata: MetadataSnapshot) -> Bool {
        switch self {
        case .cameraBrand, .cameraBrandValue:
            let brand = cameraBrandValue
            return metadata.cameraModel?.lowercased().contains(brand.lowercased()) ?? false

        case .focalLength35mmLess, .focalLength35mmValue:
            return (metadata.focalLengthIn35mm ?? 0) < focalLength35mmValue

        case .focalLength35mmMore:
            return (metadata.focalLengthIn35mm ?? 0) > focalLength35mmValue

        case .isoLess, .isoValue:
            return (metadata.iso ?? 0) < isoValue

        case .isoMore:
            return (metadata.iso ?? 0) > isoValue

        case .apertureLess, .apertureValue:
            return (metadata.aperture ?? 0) < apertureValue

        case .apertureMore:
            return (metadata.aperture ?? 0) > apertureValue

        case .flashFired:
            return metadata.flashFired == true

        case .flashNotFired:
            return metadata.flashFired == false

        case .aspectRatio, .aspectRatioValue:
            guard let width = metadata.pixelWidth, let height = metadata.pixelHeight, height > 0 else {
                return false
            }
            let actualRatio = Double(width) / Double(height)
            let targetRatio = aspectRatioValue
            // Allow ±5% tolerance for aspect ratio matching.
            let tolerance = targetRatio * 0.05
            return abs(actualRatio - targetRatio) <= tolerance

        case .imageStabilization:
            // TODO: Image stabilization is not currently captured in MetadataSnapshot.
            return false

        case .lensType, .lensTypeValue:
            return metadata.lensModel?.lowercased().contains(lensTypeValue.lowercased()) ?? false

        case .lensTypeNot, .lensTypeNotValue:
            return (metadata.lensModel?.lowercased().contains(lensTypeNotValue.lowercased()) ?? false) == false
        }
    }

    /// Returns a human-readable description of the condition for display
    /// in the rule editor.
    var description: String {
        switch self {
        case .cameraBrand, .cameraBrandValue:
            return "Camera contains '\(cameraBrandValue)'"
        case .focalLength35mmLess, .focalLength35mmValue:
            return "35mm eq. focal length < \(Int(focalLength35mmValue))mm"
        case .focalLength35mmMore:
            return "35mm eq. focal length > \(Int(focalLength35mmValue))mm"
        case .isoLess, .isoValue:
            return "ISO < \(isoValue)"
        case .isoMore:
            return "ISO > \(isoValue)"
        case .apertureLess, .apertureValue:
            return "Aperture < f/\(String(format: "%.1f", apertureValue))"
        case .apertureMore:
            return "Aperture > f/\(String(format: "%.1f", apertureValue))"
        case .flashFired:
            return "Flash fired"
        case .flashNotFired:
            return "Flash did not fire"
        case .aspectRatio, .aspectRatioValue:
            return "Aspect ratio ≈ \(String(format: "%.2f", aspectRatioValue))"
        case .imageStabilization:
            return "Image stabilization detected"
        case .lensType, .lensTypeValue:
            return "Lens contains '\(lensTypeValue)'"
        case .lensTypeNot, .lensTypeNotValue:
            return "Lens does not contain '\(lensTypeNotValue)'"
        }
    }

    // MARK: - Extractors (for matching discriminator + value cases)

    private var cameraBrandValue: String {
        if case .cameraBrandValue(let v) = self { return v }
        return ""
    }
    private var focalLength35mmValue: Double {
        if case .focalLength35mmValue(let v) = self { return v }
        return 0
    }
    private var isoValue: Int {
        if case .isoValue(let v) = self { return v }
        return 0
    }
    private var apertureValue: Double {
        if case .apertureValue(let v) = self { return v }
        return 0
    }
    private var aspectRatioValue: Double {
        if case .aspectRatioValue(let v) = self { return v }
        return 1.5
    }
    private var lensTypeValue: String {
        if case .lensTypeValue(let v) = self { return v }
        return ""
    }
    private var lensTypeNotValue: String {
        if case .lensTypeNotValue(let v) = self { return v }
        return ""
    }
}

// MARK: - Suggested Tag

struct SuggestedTag: Codable, Sendable {
    let name: String
    let category: String?
}
