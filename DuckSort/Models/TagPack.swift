//
//  TagPack.swift
//  DuckSort
//
//  Two-tier tag-pack model:
//
//  1. `TagPackTemplate` — read-only built-in presets (Wedding, Portraits,
//     Cars, Apparel, Real Estate, Events, Sports, Products, General) that
//     ship with DuckSort. Cannot be edited; the user can only Reset them
//     to factory defaults.
//
//  2. `TagPackState` — mutable on-disk state. Every pack (built-in OR
//     user-created) has exactly one `TagPackState` keyed by `id`. Built-
//     in packs seed their state from the matching template the first
//     time the user activates them, then diverge as the user customizes
//     categories/tags. User packs start empty and grow from there.
//
//  Switching packs snapshots the active `TagPackState` into the
//  outgoing pack's id, then loads the incoming pack's state. Customizing
//  the active pack edits the state for that pack id.
//
//  All of this means: you can edit the Wedding pack, switch to Cars,
//  switch back to Wedding, and your Wedding edits are still there.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Template (immutable built-in catalog)

/// Read-only template for a built-in pack. The factory content lives
/// here and is never mutated.
struct TagPackTemplate: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let tagline: String
    let systemImage: String
    let accentColor: String

    /// Categories created in this template (in order).
    let categories: [String]
    /// Tag definitions.
    let tags: [TagSpec]

    struct TagSpec: Hashable, Sendable {
        let category: String
        let name: String
        let hotkey: String?
        let colorHex: String
    }
}

extension TagPackTemplate {
    /// Every built-in pack DuckSort ships with.
    static let allTemplates: [TagPackTemplate] = [
        wedding,
        portraits,
        cars,
        apparel,
        realEstate,
        events,
        sports,
        products,
        general
    ]

    /// First-run default when the user hasn't picked anything yet.
    static let defaultTemplateID = "general"

    static func template(id: String) -> TagPackTemplate? {
        allTemplates.first { $0.id == id }
    }

    // MARK: - Built-in definitions

    static let wedding = TagPackTemplate(
        id: "wedding",
        name: "Wedding",
        tagline: "Couples, ceremony, reception.",
        systemImage: "heart",
        accentColor: "#F472B6",
        categories: ["People", "Scene", "Moment"],
        tags: [
            .init(category: "People", name: "Bride",         hotkey: "a", colorHex: "#F472B6"),
            .init(category: "People", name: "Groom",         hotkey: "b", colorHex: "#60A5FA"),
            .init(category: "People", name: "Family",        hotkey: "c", colorHex: "#FBBF24"),
            .init(category: "People", name: "Wedding Party", hotkey: "d", colorHex: "#A78BFA"),
            .init(category: "Scene",  name: "Ceremony",      hotkey: "e", colorHex: "#4ECDC4"),
            .init(category: "Scene",  name: "Reception",     hotkey: "f", colorHex: "#48BFE3"),
            .init(category: "Scene",  name: "Portraits",     hotkey: "g", colorHex: "#FB923C"),
            .init(category: "Scene",  name: "Details",       hotkey: "h", colorHex: "#94A3B8"),
            .init(category: "Moment", name: "First Look",    hotkey: "j", colorHex: "#EC4899"),
            .init(category: "Moment", name: "First Kiss",    hotkey: "k", colorHex: "#F59E0B"),
            .init(category: "Moment", name: "Dancing",       hotkey: "l", colorHex: "#A78BFA"),
            .init(category: "Moment", name: "Speeches",      hotkey: "m", colorHex: "#10B981")
        ]
    )

    static let portraits = TagPackTemplate(
        id: "portraits",
        name: "Portraits",
        tagline: "Individuals, families, headshots.",
        systemImage: "person.crop.square",
        accentColor: "#A78BFA",
        categories: ["Subject", "Style", "Lighting"],
        tags: [
            .init(category: "Subject", name: "Solo",     hotkey: "a", colorHex: "#A78BFA"),
            .init(category: "Subject", name: "Couple",   hotkey: "b", colorHex: "#F472B6"),
            .init(category: "Subject", name: "Family",   hotkey: "c", colorHex: "#FBBF24"),
            .init(category: "Subject", name: "Kids",     hotkey: "d", colorHex: "#34D399"),
            .init(category: "Subject", name: "Pets",     hotkey: "e", colorHex: "#FB923C"),
            .init(category: "Style",   name: "Studio",   hotkey: "f", colorHex: "#60A5FA"),
            .init(category: "Style",   name: "Outdoor",  hotkey: "g", colorHex: "#22C55E"),
            .init(category: "Style",   name: "Lifestyle",hotkey: "h", colorHex: "#FB7185"),
            .init(category: "Style",   name: "Headshot", hotkey: "j", colorHex: "#94A3B8"),
            .init(category: "Lighting",name: "Natural",  hotkey: "k", colorHex: "#FCD34D"),
            .init(category: "Lighting",name: "Strobe",   hotkey: "l", colorHex: "#38BDF8"),
            .init(category: "Lighting",name: "Mixed",    hotkey: "m", colorHex: "#C084FC")
        ]
    )

    static let cars = TagPackTemplate(
        id: "cars",
        name: "Cars",
        tagline: "Automotive shoots — exterior, interior, detail.",
        systemImage: "car",
        accentColor: "#EF4444",
        categories: ["View", "Angle", "Detail"],
        tags: [
            .init(category: "View",  name: "Exterior",   hotkey: "a", colorHex: "#EF4444"),
            .init(category: "View",  name: "Interior",   hotkey: "b", colorHex: "#8B5CF6"),
            .init(category: "View",  name: "Engine",     hotkey: "c", colorHex: "#F97316"),
            .init(category: "View",  name: "Underside",  hotkey: "d", colorHex: "#64748B"),
            .init(category: "Angle", name: "Front 3/4",  hotkey: "e", colorHex: "#0EA5E9"),
            .init(category: "Angle", name: "Side Profile", hotkey: "f", colorHex: "#22C55E"),
            .init(category: "Angle", name: "Rear 3/4",   hotkey: "g", colorHex: "#F59E0B"),
            .init(category: "Angle", name: "Top Down",   hotkey: "h", colorHex: "#A78BFA"),
            .init(category: "Detail",name: "Wheel",      hotkey: "j", colorHex: "#94A3B8"),
            .init(category: "Detail",name: "Headlight",  hotkey: "k", colorHex: "#FCD34D"),
            .init(category: "Detail",name: "Badge",      hotkey: "l", colorHex: "#EC4899"),
            .init(category: "Detail",name: "Dashboard",  hotkey: "m", colorHex: "#38BDF8")
        ]
    )

    static let apparel = TagPackTemplate(
        id: "apparel",
        name: "Apparel",
        tagline: "Clothing, accessories, lookbooks.",
        systemImage: "tshirt",
        accentColor: "#EC4899",
        categories: ["Product", "Shot", "Look"],
        tags: [
            .init(category: "Product", name: "Top",       hotkey: "a", colorHex: "#EC4899"),
            .init(category: "Product", name: "Bottom",    hotkey: "b", colorHex: "#8B5CF6"),
            .init(category: "Product", name: "Dress",     hotkey: "c", colorHex: "#F472B6"),
            .init(category: "Product", name: "Outerwear", hotkey: "d", colorHex: "#64748B"),
            .init(category: "Product", name: "Accessory", hotkey: "e", colorHex: "#F59E0B"),
            .init(category: "Product", name: "Footwear",  hotkey: "f", colorHex: "#22C55E"),
            .init(category: "Shot",    name: "Flat Lay",   hotkey: "g", colorHex: "#60A5FA"),
            .init(category: "Shot",    name: "On Model",   hotkey: "h", colorHex: "#A78BFA"),
            .init(category: "Shot",    name: "Hanger",     hotkey: "j", colorHex: "#94A3B8"),
            .init(category: "Shot",    name: "Detail",     hotkey: "k", colorHex: "#FCD34D"),
            .init(category: "Look",    name: "Hero",       hotkey: "l", colorHex: "#FB7185"),
            .init(category: "Look",    name: "Lifestyle",  hotkey: "m", colorHex: "#34D399")
        ]
    )

    static let realEstate = TagPackTemplate(
        id: "realestate",
        name: "Real Estate",
        tagline: "Listings, interiors, exteriors.",
        systemImage: "house",
        accentColor: "#0EA5E9",
        categories: ["Space", "Shot", "Feature"],
        tags: [
            .init(category: "Space",  name: "Living",     hotkey: "a", colorHex: "#0EA5E9"),
            .init(category: "Space",  name: "Kitchen",    hotkey: "b", colorHex: "#F97316"),
            .init(category: "Space",  name: "Bedroom",    hotkey: "c", colorHex: "#A78BFA"),
            .init(category: "Space",  name: "Bathroom",   hotkey: "d", colorHex: "#22C55E"),
            .init(category: "Space",  name: "Office",     hotkey: "e", colorHex: "#60A5FA"),
            .init(category: "Space",  name: "Outdoor",    hotkey: "f", colorHex: "#34D399"),
            .init(category: "Shot",   name: "Front",      hotkey: "g", colorHex: "#F59E0B"),
            .init(category: "Shot",   name: "Rear",       hotkey: "h", colorHex: "#8B5CF6"),
            .init(category: "Shot",   name: "Wide",       hotkey: "j", colorHex: "#38BDF8"),
            .init(category: "Shot",   name: "Detail",     hotkey: "k", colorHex: "#FCD34D"),
            .init(category: "Feature",name: "Pool",       hotkey: "l", colorHex: "#06B6D4"),
            .init(category: "Feature",name: "View",       hotkey: "m", colorHex: "#10B981")
        ]
    )

    static let events = TagPackTemplate(
        id: "events",
        name: "Events",
        tagline: "Concerts, conferences, parties.",
        systemImage: "music.mic",
        accentColor: "#F59E0B",
        categories: ["Moment", "Crowd", "Production"],
        tags: [
            .init(category: "Moment",    name: "Keynote",     hotkey: "a", colorHex: "#F59E0B"),
            .init(category: "Moment",    name: "Performance", hotkey: "b", colorHex: "#EC4899"),
            .init(category: "Moment",    name: "Awards",      hotkey: "c", colorHex: "#FCD34D"),
            .init(category: "Moment",    name: "Candid",      hotkey: "d", colorHex: "#A78BFA"),
            .init(category: "Crowd",     name: "Wide Crowd",  hotkey: "e", colorHex: "#60A5FA"),
            .init(category: "Crowd",     name: "Engaged",     hotkey: "f", colorHex: "#22C55E"),
            .init(category: "Crowd",     name: "Reaction",    hotkey: "g", colorHex: "#FB7185"),
            .init(category: "Production",name: "Stage",       hotkey: "h", colorHex: "#94A3B8"),
            .init(category: "Production",name: "Lighting",    hotkey: "j", colorHex: "#FCD34D"),
            .init(category: "Production",name: "Backstage",   hotkey: "k", colorHex: "#64748B")
        ]
    )

    static let sports = TagPackTemplate(
        id: "sports",
        name: "Sports",
        tagline: "Action, athletes, game moments.",
        systemImage: "sportscourt",
        accentColor: "#22C55E",
        categories: ["Sport", "Moment", "Shot"],
        tags: [
            .init(category: "Sport",  name: "Team Sport", hotkey: "a", colorHex: "#22C55E"),
            .init(category: "Sport",  name: "Individual", hotkey: "b", colorHex: "#A78BFA"),
            .init(category: "Sport",  name: "Water",      hotkey: "c", colorHex: "#0EA5E9"),
            .init(category: "Sport",  name: "Extreme",    hotkey: "d", colorHex: "#EF4444"),
            .init(category: "Moment", name: "Action",     hotkey: "e", colorHex: "#F97316"),
            .init(category: "Moment", name: "Emotion",    hotkey: "f", colorHex: "#F472B6"),
            .init(category: "Moment", name: "Victory",    hotkey: "g", colorHex: "#FCD34D"),
            .init(category: "Moment", name: "Pre-Game",   hotkey: "h", colorHex: "#94A3B8"),
            .init(category: "Shot",   name: "Tight",      hotkey: "j", colorHex: "#60A5FA"),
            .init(category: "Shot",   name: "Wide",       hotkey: "k", colorHex: "#34D399"),
            .init(category: "Shot",   name: "Behind",     hotkey: "l", colorHex: "#8B5CF6"),
            .init(category: "Shot",   name: "Drone",      hotkey: "m", colorHex: "#06B6D4")
        ]
    )

    static let products = TagPackTemplate(
        id: "products",
        name: "Products",
        tagline: "Catalog, e-commerce, packaging.",
        systemImage: "shippingbox",
        accentColor: "#8B5CF6",
        categories: ["Type", "Angle", "Use"],
        tags: [
            .init(category: "Type",  name: "Hero Shot",  hotkey: "a", colorHex: "#8B5CF6"),
            .init(category: "Type",  name: "Group",      hotkey: "b", colorHex: "#EC4899"),
            .init(category: "Type",  name: "Packaging",  hotkey: "c", colorHex: "#F59E0B"),
            .init(category: "Type",  name: "Lifestyle",  hotkey: "d", colorHex: "#34D399"),
            .init(category: "Angle", name: "Front",      hotkey: "e", colorHex: "#60A5FA"),
            .init(category: "Angle", name: "Side",       hotkey: "f", colorHex: "#A78BFA"),
            .init(category: "Angle", name: "Top Down",   hotkey: "g", colorHex: "#FB923C"),
            .init(category: "Angle", name: "45°",        hotkey: "h", colorHex: "#22C55E"),
            .init(category: "Use",   name: "Web",        hotkey: "j", colorHex: "#0EA5E9"),
            .init(category: "Use",   name: "Print",      hotkey: "k", colorHex: "#FBBF24"),
            .init(category: "Use",   name: "Social",     hotkey: "l", colorHex: "#F472B6")
        ]
    )

    static let general = TagPackTemplate(
        id: "general",
        name: "General",
        tagline: "Small neutral starter set — works for anything.",
        systemImage: "tag",
        accentColor: "#4A90E2",
        categories: ["Status", "Type"],
        tags: [
            .init(category: "Status", name: "Keepers",   hotkey: "a", colorHex: "#22C55E"),
            .init(category: "Status", name: "Maybe",     hotkey: "b", colorHex: "#F59E0B"),
            .init(category: "Status", name: "Rejects",   hotkey: "c", colorHex: "#EF4444"),
            .init(category: "Type",   name: "Hero",      hotkey: "d", colorHex: "#8B5CF6"),
            .init(category: "Type",   name: "Detail",    hotkey: "e", colorHex: "#0EA5E9"),
            .init(category: "Type",   name: "Wide",      hotkey: "f", colorHex: "#60A5FA"),
            .init(category: "Type",   name: "Candid",    hotkey: "g", colorHex: "#EC4899")
        ]
    )
}

// MARK: - State (mutable per-pack on-disk content)

/// Mutable on-disk state for a tag pack. Built-in packs start equal to
/// their template; user-created packs start empty. Either way, after the
/// user activates a pack and starts customizing it, this struct holds
/// the live categories + tags that should reappear next time the pack
/// is activated.
struct TagPackState: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var tagline: String
    var systemImage: String
    var accentColor: String

    /// True for the built-in catalog entries; false for user-created packs.
    /// The user can't edit/delete a built-in pack, but can still reset it.
    let isBuiltIn: Bool

    var categories: [CategoryEntry]
    var tags: [TagEntry]

    /// Lightweight serializable category (no need for a fresh UUID here;
    /// we generate UUIDs when the state is materialized into TagStore).
    struct CategoryEntry: Codable, Hashable, Sendable {
        var name: String
    }

    struct TagEntry: Codable, Hashable, Sendable {
        var category: String
        var name: String
        var hotkey: String?
        var colorHex: String
    }

    init(
        id: String,
        name: String,
        tagline: String = "",
        systemImage: String = "tag",
        accentColor: String = "#4A90E2",
        isBuiltIn: Bool,
        categories: [CategoryEntry],
        tags: [TagEntry]
    ) {
        self.id = id
        self.name = name
        self.tagline = tagline
        self.systemImage = systemImage
        self.accentColor = accentColor
        self.isBuiltIn = isBuiltIn
        self.categories = categories
        self.tags = tags
    }

    /// Construct a state from a template (factory-fresh state).
    static func from(template: TagPackTemplate) -> TagPackState {
        TagPackState(
            id: template.id,
            name: template.name,
            tagline: template.tagline,
            systemImage: template.systemImage,
            accentColor: template.accentColor,
            isBuiltIn: true,
            categories: template.categories.map { CategoryEntry(name: $0) },
            tags: template.tags.map {
                TagEntry(category: $0.category, name: $0.name,
                         hotkey: $0.hotkey, colorHex: $0.colorHex)
            }
        )
    }

    /// Empty state for a brand-new user-created pack.
    static func empty(id: String, name: String) -> TagPackState {
        TagPackState(
            id: id,
            name: name,
            tagline: "Custom pack",
            systemImage: "rectangle.stack",
            accentColor: "#4A90E2",
            isBuiltIn: false,
            categories: [],
            tags: []
        )
    }
}

// MARK: - Codable on-disk file

struct TagPackLibraryFile: Codable {
    var version: Int = 1
    var packs: [TagPackState]
}

// MARK: - Public file format (.tagpack.json)

extension UTType {
    /// Custom file type for an exported tag pack. Users can save and
    /// share these as `.tagpack.json` files.
    static var tagPack: UTType {
        UTType(exportedAs: "com.ducksort.tagpack")
    }
}

extension TagPackState {
    /// Serializable representation used for import/export. Identical to
    /// the on-disk library file minus the version envelope.
    struct ExportPayload: Codable {
        var id: String
        var name: String
        var tagline: String
        var systemImage: String
        var accentColor: String
        var categories: [CategoryEntry]
        var tags: [TagEntry]

        init(state: TagPackState) {
            self.id = state.id
            self.name = state.name
            self.tagline = state.tagline
            self.systemImage = state.systemImage
            self.accentColor = state.accentColor
            self.categories = state.categories
            self.tags = state.tags
        }

        /// Promote an exported payload back to a full state. Marks it as
        /// user-created regardless of its origin id so the user can edit.
        func toState(isBuiltIn: Bool = false) -> TagPackState {
            TagPackState(
                id: id,
                name: name,
                tagline: tagline,
                systemImage: systemImage,
                accentColor: accentColor,
                isBuiltIn: isBuiltIn,
                categories: categories,
                tags: tags
            )
        }
    }

    /// Encode this state to a JSON document suitable for export.
    func encodedForExport() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(ExportPayload(state: self))
    }

    /// Decode an exported `.tagpack.json` file.
    static func decodedFromImport(_ data: Data) throws -> TagPackState {
        let decoder = JSONDecoder()
        return try decoder.decode(ExportPayload.self, from: data).toState()
    }
}

// MARK: - Legacy compatibility

/// Backwards-compatible alias. Code outside this file that still uses
/// `TagPack` / `TagPack.pack(id:)` should be updated, but a typealias
/// keeps older call sites compiling during the transition.
typealias TagPack = TagPackTemplate

extension TagPackTemplate {
    /// Backwards-compatible static accessors used by older call sites.
    static let allPacks: [TagPackTemplate] = TagPackTemplate.allTemplates
    static let defaultPackID: String = TagPackTemplate.defaultTemplateID
    static func pack(id: String) -> TagPackTemplate? {
        TagPackTemplate.template(id: id)
    }
}
