//
//  CustomTag.swift
//  PhotomatorSort
//
//  User-defined tag and tag category model. Replaces the old color-only
//  TagProfile for export routing. Each tag belongs to exactly one category
//  and can be applied to any number of photos.
//

import Foundation
import SwiftUI

// MARK: - Tag Category

struct TagCategory: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }

    static let defaults: [TagCategory] = [
        TagCategory(name: "People"),
        TagCategory(name: "Scene"),
        TagCategory(name: "Action")
    ]
}

// MARK: - Custom Tag

struct CustomTag: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var categoryID: UUID
    var hotkey: String?
    var colorHex: String

    init(
        id: UUID = UUID(),
        name: String,
        categoryID: UUID,
        hotkey: String? = nil,
        colorHex: String = "#4A90E2"
    ) {
        self.id = id
        self.name = name
        self.categoryID = categoryID
        self.hotkey = hotkey
        self.colorHex = colorHex
    }

    var color: Color {
        Color(hex: colorHex) ?? .accentColor
    }

    var shortcutInfo: KeyboardShortcutInfo? {
        guard let hotkey = hotkey, !hotkey.isEmpty else { return nil }
        return KeyboardShortcutInfo.parse(hotkey)
    }
}

// MARK: - Keyboard Shortcut Info

struct KeyboardShortcutInfo: Hashable, Sendable {
    var key: String
    var shift: Bool = false
    var control: Bool = false
    var option: Bool = false
    var command: Bool = false

    static func parse(_ string: String) -> KeyboardShortcutInfo {
        let parts = string.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        var info = KeyboardShortcutInfo(key: "")
        for part in parts {
            if part == "cmd" || part == "command" || part == "⌘" {
                info.command = true
            } else if part == "shift" || part == "⇧" {
                info.shift = true
            } else if part == "opt" || part == "option" || part == "alt" || part == "⌥" {
                info.option = true
            } else if part == "ctrl" || part == "control" || part == "⌃" {
                info.control = true
            } else {
                info.key = part
            }
        }
        return info
    }

    var serializedString: String {
        var parts: [String] = []
        if control { parts.append("ctrl") }
        if option { parts.append("opt") }
        if shift { parts.append("shift") }
        if command { parts.append("cmd") }
        parts.append(key)
        return parts.joined(separator: "+")
    }

    var displayString: String {
        var parts: [String] = []
        if control { parts.append("⌃") }
        if option { parts.append("⌥") }
        if shift { parts.append("⇧") }
        if command { parts.append("⌘") }
        
        let keyLabel = key.count == 1 ? key.uppercased() : key.capitalized
        parts.append(keyLabel)
        return parts.joined()
    }
}

// MARK: - Photo Tag Assignment

struct PhotoTagAssignment: Codable, Identifiable, Hashable, Sendable {
    var id: UUID { photoSetID }
    var photoSetID: UUID
    var tagIDs: Set<UUID>

    init(photoSetID: UUID, tagIDs: Set<UUID> = []) {
        self.photoSetID = photoSetID
        self.tagIDs = tagIDs
    }
}

// MARK: - Color hex helper

extension Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
        let r = Double((value & 0xFF0000) >> 16) / 255.0
        let g = Double((value & 0x00FF00) >> 8) / 255.0
        let b = Double(value & 0x0000FF) / 255.0
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: 1.0)
    }
}
