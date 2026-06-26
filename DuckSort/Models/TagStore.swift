//
//  TagStore.swift
//  PhotomatorSort
//
//  Observable container for tag categories, custom tags, and per-photo
//  assignments. Persists everything to JSON on disk and loads on init.
//

import Foundation
import SwiftUI

@MainActor
final class TagStore: ObservableObject {

    @Published private(set) var categories: [TagCategory] = []
    @Published private(set) var tags: [CustomTag] = []
    @Published private(set) var assignments: [UUID: PhotoTagAssignment] = [:]


    private let storeURL: URL

    // Cache dictionaries for fast lookups
    private var tagsByCategoryID: [UUID: [CustomTag]] = [:]
    private var tagsByID: [UUID: CustomTag] = [:]
    private var tagsByName: [String: CustomTag] = [:]
    /// O(1) lookup of a tag by its parsed keyboard shortcut. Rebuilt
    /// inside `updateIndexes()` so `ContentView` doesn't have to iterate
    /// every tag + re-parse hotkey strings on every keypress.
    private var tagsByShortcut: [KeyboardShortcutInfo: CustomTag] = [:]
    /// O(1) lookup of a `Color` for a tag's hex string. Cleared whenever
    /// `updateIndexes()` runs so stale colors don't leak after edits.
    private var colorCache: [String: Color] = [:]
    private var categoryNamesByID: [UUID: String] = [:]
    private var categoriesByID: [UUID: TagCategory] = [:]

    private var saveTask: Task<Void, Never>? = nil

    private struct PersistedShape: Codable {
        var categories: [TagCategory]
        var tags: [CustomTag]
        var assignments: [PhotoTagAssignment]
    }

    private func updateIndexes() {
        tagsByCategoryID = Dictionary(grouping: tags, by: { $0.categoryID })
        tagsByID = Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0) })
        tagsByName = tags.reduce(into: [String: CustomTag]()) { dict, tag in
            dict[tag.name] = tag
        }
        tagsByShortcut = [:]
        for tag in tags {
            if let shortcut = tag.shortcutInfo {
                tagsByShortcut[shortcut] = tag
            }
        }
        // Color cache must be invalidated alongside the tag list since
        // hex strings can change on edit and old entries would be stale.
        colorCache = [:]
        categoryNamesByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.name) })
        categoriesByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
    }

    init() {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        let folder = appSupport.appendingPathComponent("DuckSort", isDirectory: true)
        let oldFolder = appSupport.appendingPathComponent("PhotomatorSort", isDirectory: true)
        
        if !FileManager.default.fileExists(atPath: folder.path) && FileManager.default.fileExists(atPath: oldFolder.path) {
            try? FileManager.default.moveItem(at: oldFolder, to: folder)
        }
        
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        self.storeURL = folder.appendingPathComponent("tags.json")
        load()
        if categories.isEmpty && tags.isEmpty {
            seedDefaults()
        }
    }

    // MARK: - Lookup helpers

    func category(id: UUID) -> TagCategory? {
        categoriesByID[id]
    }

    func categoryName(id: UUID) -> String? {
        categoryNamesByID[id]
    }

    func tags(in categoryID: UUID) -> [CustomTag] {
        tagsByCategoryID[categoryID] ?? []
    }

    func tag(id: UUID) -> CustomTag? {
        tagsByID[id]
    }

    func assignedTags(for photoSetID: UUID) -> [CustomTag] {
        guard let assignment = assignments[photoSetID] else { return [] }
        return assignment.tagIDs.compactMap { tagsByID[$0] }
    }

    func assignedTagIDs(for photoSetID: UUID) -> Set<UUID> {
        assignments[photoSetID]?.tagIDs ?? []
    }

    /// O(1) lookup of a tag by its parsed keyboard shortcut. Used by the
    /// global keypress monitor so it doesn't have to iterate every tag and
    /// re-parse its hotkey string on every key event.
    func tag(for shortcut: KeyboardShortcutInfo) -> CustomTag? {
        tagsByShortcut[shortcut]
    }

    /// Cached `Color` for a tag's hex string. Called many times per layout
    /// pass (cells, pills, sidebar, filmstrip, XMP inspector, settings)
    /// so avoiding the per-call hex parse adds up.
    func color(for tag: CustomTag) -> Color {
        if let cached = colorCache[tag.colorHex] { return cached }
        let color = Color(hex: tag.colorHex) ?? .accentColor
        colorCache[tag.colorHex] = color
        return color
    }

    // MARK: - Category management

    @discardableResult
    func addCategory(name: String) -> TagCategory {
        let category = TagCategory(name: name)
        categories.append(category)
        updateIndexes()
        save()
        return category
    }

    func renameCategory(id: UUID, to name: String) {
        guard let index = categories.firstIndex(where: { $0.id == id }) else { return }
        categories[index].name = name
        updateIndexes()
        save()
    }

    func deleteCategory(id: UUID) {
        let removedTagIDs = Set(tags.filter { $0.categoryID == id }.map(\.id))
        categories.removeAll { $0.id == id }
        tags.removeAll { $0.categoryID == id }
        for key in assignments.keys {
            assignments[key]?.tagIDs.subtract(removedTagIDs)
        }
        updateIndexes()
        save()
    }

    // MARK: - Tag management

    @discardableResult
    func addTag(name: String, categoryID: UUID, hotkey: String? = nil, colorHex: String? = nil) -> CustomTag {
        let palette = [
            "#FF6B6B", // Coral Red
            "#FFA94D", // Pastel Orange
            "#FFD43B", // Yellow Gold
            "#4ECDC4", // Mint Teal
            "#4D96FF", // Royal Blue
            "#A78BFA", // Lavender Purple
            "#F472B6", // Warm Rose
            "#6BCB77", // Soft Green
            "#38BDF8", // Sky Blue
            "#FB923C", // Tangerine
            "#A7F3D0", // Emerald Green
            "#C084FC"  // Orchid Purple
        ]
        
        let selectedColor = colorHex ?? palette[tags.count % palette.count]
        let tag = CustomTag(name: name, categoryID: categoryID, hotkey: sanitizedHotkey(hotkey), colorHex: selectedColor)
        tags.append(tag)
        updateIndexes()
        save()
        return tag
    }

    func updateTag(_ tag: CustomTag) {
        guard let index = tags.firstIndex(where: { $0.id == tag.id }) else { return }
        var updated = tag
        updated.hotkey = sanitizedHotkey(tag.hotkey, excluding: tag.id)
        tags[index] = updated
        updateIndexes()
        save()
    }

    func deleteTag(id: UUID) {
        tags.removeAll { $0.id == id }
        for key in assignments.keys {
            assignments[key]?.tagIDs.remove(id)
        }
        updateIndexes()
        save()
    }

    /// Wipe every category, tag, and per-photo tag assignment. Used when
    /// the user picks a new tag pack during onboarding or hits "Reset tag
    /// pack" in Settings → Tags.
    func clearAllTags() {
        tags.removeAll()
        categories.removeAll()
        assignments.removeAll()
        updateIndexes()
        save()
    }

    /// Clear every tag's hotkey without touching categories, tag names, or
    /// assignments. Useful when hotkeys have collided and the user wants
    /// to start over.
    func clearAllHotkeys() {
        for index in tags.indices {
            tags[index].hotkey = nil
        }
        updateIndexes()
        save()
    }

    /// Replace every category and tag with the contents of ``pack``. Used
    /// by the onboarding wizard when the user picks a template. Existing
    /// assignments are dropped because their tag IDs no longer exist.
    func applyPack(_ pack: TagPackTemplate) {
        var newCategories: [TagCategory] = []
        for name in pack.categories {
            newCategories.append(TagCategory(name: name))
        }
        var newTags: [CustomTag] = []
        for spec in pack.tags {
            guard let category = newCategories.first(where: { $0.name == spec.category })
            else { continue }
            newTags.append(CustomTag(
                name: spec.name,
                categoryID: category.id,
                hotkey: spec.hotkey,
                colorHex: spec.colorHex
            ))
        }
        categories = newCategories
        tags = newTags
        sanitizeAllHotkeys()
        assignments.removeAll()
        updateIndexes()
        save()
    }

    /// Replace categories + tags with the contents of a saved `TagPackState`.
    /// Used by `TagPackLibrary` when switching between packs so each pack
    /// has its own independently-edited state.
    func applyPackState(_ state: TagPackState) {
        var newCategories: [TagCategory] = []
        var seenNames = Set<String>()
        for entry in state.categories {
            guard !seenNames.contains(entry.name) else { continue }
            seenNames.insert(entry.name)
            newCategories.append(TagCategory(name: entry.name))
        }
        var newTags: [CustomTag] = []
        for entry in state.tags {
            guard let category = newCategories.first(where: { $0.name == entry.category })
            else { continue }
            newTags.append(CustomTag(
                name: entry.name,
                categoryID: category.id,
                hotkey: entry.hotkey,
                colorHex: entry.colorHex
            ))
        }
        categories = newCategories
        tags = newTags
        sanitizeAllHotkeys()
        assignments.removeAll()
        updateIndexes()
        save()
    }

    // MARK: - Assignment management

    func setTags(_ tagIDs: Set<UUID>, for photoSetID: UUID) {
        let filtered = tagIDs.filter { tagsByID[$0] != nil }
        if filtered.isEmpty {
            assignments.removeValue(forKey: photoSetID)
        } else {
            assignments[photoSetID] = PhotoTagAssignment(photoSetID: photoSetID, tagIDs: Set(filtered))
        }
        save()
    }

    func setTagsBatch(_ batch: [UUID: Set<UUID>]) {
        for (photoSetID, tagIDs) in batch {
            let filtered = tagIDs.filter { tagsByID[$0] != nil }
            if filtered.isEmpty {
                assignments.removeValue(forKey: photoSetID)
            } else {
                assignments[photoSetID] = PhotoTagAssignment(photoSetID: photoSetID, tagIDs: Set(filtered))
            }
        }
        save()
    }

    func toggleTag(_ tagID: UUID, for photoSetID: UUID) {
        var current = assignments[photoSetID]?.tagIDs ?? []
        if current.contains(tagID) {
            current.remove(tagID)
        } else {
            current.insert(tagID)
        }
        setTags(current, for: photoSetID)
    }

    func addTag(_ tagID: UUID, to photoSetID: UUID) {
        var current = assignments[photoSetID]?.tagIDs ?? []
        current.insert(tagID)
        setTags(current, for: photoSetID)
    }

    func removeTag(_ tagID: UUID, from photoSetID: UUID) {
        var current = assignments[photoSetID]?.tagIDs ?? []
        current.remove(tagID)
        setTags(current, for: photoSetID)
    }

    func clearTags(for photoSetID: UUID) {
        assignments.removeValue(forKey: photoSetID)
        save()
    }

    // MARK: - Persistence

    func load() {
        guard FileManager.default.fileExists(atPath: storeURL.path) else {
            return
        }
        do {
            let data = try Data(contentsOf: storeURL)
            let decoded = try JSONDecoder().decode(PersistedShape.self, from: data)
            categories = decoded.categories
            tags = decoded.tags
            let map = Dictionary(uniqueKeysWithValues: decoded.assignments.map { ($0.photoSetID, $0) })
            assignments = map
            sanitizeAllHotkeys()
            updateIndexes()
        } catch {
            print("Failed to load TagStore JSON: \(error)")
        }
    }

    func save() {
        saveTask?.cancel()
        saveTask = Task {
            do {
                try await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled else { return }
                performSave()
            } catch {
                // Task was cancelled
            }
        }
    }

    private func performSave() {
        let shape = PersistedShape(
            categories: categories,
            tags: tags,
            assignments: Array(assignments.values)
        )
        do {
            let data = try JSONEncoder().encode(shape)
            try data.write(to: storeURL, options: .atomic)
        } catch {
            print("Failed to save TagStore JSON: \(error)")
        }
    }

    // MARK: - Default seeding

    private func seedDefaults() {
        // First-launch defaults use the neutral General pack so new users
        // aren't locked into a specific shoot type. They can swap to a
        // specialized pack anytime from Settings → Tags or Help → Show
        // Welcome Guide.
        if let pack = TagPack.pack(id: TagPack.defaultPackID) {
            applyPack(pack)
        }
    }

    private func sanitizedHotkey(_ hotkey: String?, excluding tagID: UUID? = nil) -> String? {
        guard let hotkey, !hotkey.isEmpty else { return nil }
        guard TagHotkeyRules.reservedReason(for: hotkey) == nil else { return nil }
        let duplicate = tags.contains { other in
            other.id != tagID && other.hotkey == hotkey
        }
        return duplicate ? nil : hotkey
    }

    private func sanitizeAllHotkeys() {
        var seen = Set<String>()
        for index in tags.indices {
            guard let hotkey = tags[index].hotkey, !hotkey.isEmpty else { continue }
            if TagHotkeyRules.reservedReason(for: hotkey) != nil || seen.contains(hotkey) {
                tags[index].hotkey = nil
            } else {
                seen.insert(hotkey)
            }
        }
    }
}
