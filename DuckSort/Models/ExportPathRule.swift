//
//  ExportPathRule.swift
//  PhotomatorSort
//
//  Folder rules used to build the destination path for a photo during
//  copy, move, or JPEG export. Rules are an ordered list of components.
//  Each component contributes one folder level beneath the base destination.
//

import Foundation

enum ExportPathComponent: Codable, Hashable, Identifiable, Sendable {
    case cameraModel
    case lensModel
    case captureDate
    case tagCategory(UUID)        // category id
    case customText(String)

    var id: String {
        switch self {
        case .cameraModel:            return "cameraModel"
        case .lensModel:              return "lensModel"
        case .captureDate:            return "captureDate"
        case .tagCategory(let id):    return "tagCategory:\(id.uuidString)"
        case .customText(let text):   return "customText:\(text)"
        }
    }

    var displayName: String {
        switch self {
        case .cameraModel:            return "Camera Model"
        case .lensModel:              return "Lens Model"
        case .captureDate:            return "Capture Date"
        case .tagCategory:            return "Tag Category"
        case .customText:             return "Custom Text"
        }
    }

    var systemImage: String {
        switch self {
        case .cameraModel:            return "camera"
        case .lensModel:              return "camera.macro"
        case .captureDate:            return "calendar"
        case .tagCategory:            return "tag"
        case .customText:             return "textformat"
        }
    }
}

struct ExportPathRule: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var components: [ExportPathComponent]

    init(
        id: UUID = UUID(),
        name: String = "Untitled Rule",
        components: [ExportPathComponent] = []
    ) {
        self.id = id
        self.name = name
        self.components = components
    }

    static let defaultRule: ExportPathRule = ExportPathRule(
        name: "Camera / People / Scene / Action",
        components: [.cameraModel, .tagCategory(UUID()), .tagCategory(UUID()), .tagCategory(UUID())]
    )
}

// MARK: - Router

enum ExportPathRouter {
    /// Build a destination folder for a single photo by walking the rule's components.
    /// Tag categories are resolved using `categoryNameProvider` (category id -> name).
    static func destinationFolders(
        base: URL,
        rule: [ExportPathComponent],
        metadata: MetadataSnapshot,
        assignedTags: [CustomTag],
        categoryNameProvider: (UUID) -> String?,
        dateFolderFormatter: (Date) -> String = defaultDateFolderFormatter
    ) -> [URL] {
        var currentFolders: [URL] = [base]

        for component in rule {
            var nextFolders: [URL] = []
            for folder in currentFolders {
                switch component {
                case .cameraModel:
                    let name = FilenameSanitizer.clean(
                        metadata.cameraModel ?? "",
                        fallback: "Unknown Camera"
                    )
                    nextFolders.append(folder.appendingPathComponent(name))

                case .lensModel:
                    let name = FilenameSanitizer.clean(
                        metadata.lensModel ?? "",
                        fallback: "Unknown Lens"
                    )
                    nextFolders.append(folder.appendingPathComponent(name))

                case .captureDate:
                    let name: String
                    if let date = metadata.captureDate {
                        name = dateFolderFormatter(date)
                    } else {
                        name = "Unknown Date"
                    }
                    nextFolders.append(folder.appendingPathComponent(name))

                case .tagCategory(let categoryID):
                    let categoryName = categoryNameProvider(categoryID) ?? "Uncategorized"
                    let matching = assignedTags
                        .filter { $0.categoryID == categoryID }
                        .map { FilenameSanitizer.clean($0.name, fallback: "Unnamed") }

                    if matching.isEmpty {
                        nextFolders.append(folder.appendingPathComponent("No \(categoryName)"))
                    } else {
                        for tag in matching {
                            nextFolders.append(folder.appendingPathComponent(tag))
                        }
                    }

                case .customText(let text):
                    let cleaned = FilenameSanitizer.clean(text, fallback: "")
                    if !cleaned.isEmpty {
                        nextFolders.append(folder.appendingPathComponent(cleaned))
                    } else {
                        nextFolders.append(folder)
                    }
                }
            }
            currentFolders = nextFolders
        }

        return currentFolders
    }

    /// Pretty-print a rule for the configuration UI.
    static func describe(
        _ rule: [ExportPathComponent],
        categoryNameProvider: (UUID) -> String?
    ) -> String {
        rule.map { component in
            switch component {
            case .cameraModel:            return "Camera"
            case .lensModel:              return "Lens"
            case .captureDate:            return "Date"
            case .tagCategory(let id):
                return categoryNameProvider(id) ?? "Tag"
            case .customText(let text):   return text
            }
        }.joined(separator: " / ")
    }

    /// Cached DateFormatter shared across every routed photo. DateFormatter
    /// creation is ~50–100µs per call; allocating one per photo on a 5,000
    /// photo transfer would cost ~0.25–0.5s for no good reason.
    private static let cachedDateFolderFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func defaultDateFolderFormatter(_ date: Date) -> String {
        cachedDateFolderFormatter.string(from: date)
    }
}
