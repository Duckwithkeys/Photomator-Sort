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

    private struct PersistedShape: Codable {
        var categories: [TagCategory]
        var tags: [CustomTag]
        var assignments: [PhotoTagAssignment]
    }

    init() {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        let folder = appSupport.appendingPathComponent("PhotomatorSort", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        self.storeURL = folder.appendingPathComponent("tags.json")
        load()
        if categories.isEmpty && tags.isEmpty {
            seedDefaults()
        }
    }

    // MARK: - Lookup helpers

    func category(id: UUID) -> TagCategory? {
        categories.first(where: { $0.id == id })
    }

    func categoryName(id: UUID) -> String? {
        category(id: id)?.name
    }

    func tags(in categoryID: UUID) -> [CustomTag] {
        tags.filter { $0.categoryID == categoryID }
    }

    func tag(id: UUID) -> CustomTag? {
        tags.first(where: { $0.id == id })
    }

    func assignedTags(for photoSetID: UUID) -> [CustomTag] {
        guard let assignment = assignments[photoSetID] else { return [] }
        return tags.filter { assignment.tagIDs.contains($0.id) }
    }

    func assignedTagIDs(for photoSetID: UUID) -> Set<UUID> {
        assignments[photoSetID]?.tagIDs ?? []
    }

    // MARK: - Category management

    @discardableResult
    func addCategory(name: String) -> TagCategory {
        let category = TagCategory(name: name)
        categories.append(category)
        save()
        return category
    }

    func renameCategory(id: UUID, to name: String) {
        guard let index = categories.firstIndex(where: { $0.id == id }) else { return }
        categories[index].name = name
        save()
    }

    func deleteCategory(id: UUID) {
        let removedTagIDs = Set(tags.filter { $0.categoryID == id }.map(\.id))
        categories.removeAll { $0.id == id }
        tags.removeAll { $0.categoryID == id }
        for key in assignments.keys {
            assignments[key]?.tagIDs.subtract(removedTagIDs)
        }
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
        let tag = CustomTag(name: name, categoryID: categoryID, hotkey: hotkey, colorHex: selectedColor)
        tags.append(tag)
        save()
        return tag
    }

    func updateTag(_ tag: CustomTag) {
        guard let index = tags.firstIndex(where: { $0.id == tag.id }) else { return }
        tags[index] = tag
        save()
    }

    func deleteTag(id: UUID) {
        tags.removeAll { $0.id == id }
        for key in assignments.keys {
            assignments[key]?.tagIDs.remove(id)
        }
        save()
    }

    // MARK: - Assignment management

    func setTags(_ tagIDs: Set<UUID>, for photoSetID: UUID) {
        let valid = Set(tags.map(\.id))
        let filtered = tagIDs.intersection(valid)
        if filtered.isEmpty {
            assignments.removeValue(forKey: photoSetID)
        } else {
            assignments[photoSetID] = PhotoTagAssignment(photoSetID: photoSetID, tagIDs: filtered)
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
        guard FileManager.default.fileExists(atPath: storeURL.path),
              let data = try? Data(contentsOf: storeURL),
              let decoded = try? JSONDecoder().decode(PersistedShape.self, from: data)
        else {
            return
        }
        categories = decoded.categories
        tags = decoded.tags
        let map = Dictionary(uniqueKeysWithValues: decoded.assignments.map { ($0.photoSetID, $0) })
        assignments = map
    }

    func save() {
        let shape = PersistedShape(
            categories: categories,
            tags: tags,
            assignments: Array(assignments.values)
        )
        guard let data = try? JSONEncoder().encode(shape) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }

    // MARK: - Default seeding

    private func seedDefaults() {
        let people = TagCategory(name: "People")
        let scene = TagCategory(name: "Scene")
        let action = TagCategory(name: "Action")
        categories = [people, scene, action]

        tags = [
            CustomTag(name: "Graduate", categoryID: people.id, hotkey: "g", colorHex: "#FF6B6B"),
            CustomTag(name: "Family",   categoryID: people.id, hotkey: "f", colorHex: "#FFA94D"),
            CustomTag(name: "Ceremony", categoryID: scene.id,  hotkey: "c", colorHex: "#4ECDC4"),
            CustomTag(name: "Reception",categoryID: scene.id,  hotkey: "r", colorHex: "#48BFE3"),
            CustomTag(name: "Walking",  categoryID: action.id, hotkey: "w", colorHex: "#A78BFA"),
            CustomTag(name: "Dancing",  categoryID: action.id, hotkey: "d", colorHex: "#F472B6")
        ]

        save()
    }
}
