//
//  ExportRuleStore.swift
//  PhotomatorSort
//
//  Observable container for saved export routing rules. Persists to JSON.
//

import Foundation
import SwiftUI

@MainActor
final class ExportRuleStore: ObservableObject {

    @Published private(set) var rules: [ExportPathRule] = []
    @Published var selectedRuleID: UUID?

    private let storeURL: URL

    private struct PersistedShape: Codable {
        var rules: [ExportPathRule]
        var selectedRuleID: UUID?
    }

    init() {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        let folder = appSupport.appendingPathComponent("PhotomatorSort", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        self.storeURL = folder.appendingPathComponent("export-rules.json")
        load()
        if rules.isEmpty {
            rules = [Self.makeDefaultRule()]
        }
        if selectedRuleID == nil {
            selectedRuleID = rules.first?.id
        }
    }

    var selectedRule: ExportPathRule? {
        guard let id = selectedRuleID else { return nil }
        return rules.first(where: { $0.id == id })
    }

    func selectRule(id: UUID) {
        selectedRuleID = id
        save()
    }

    @discardableResult
    func addRule(name: String) -> ExportPathRule {
        let rule = ExportPathRule(name: name, components: [])
        rules.append(rule)
        selectedRuleID = rule.id
        save()
        return rule
    }

    func updateRule(_ rule: ExportPathRule) {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        rules[index] = rule
        save()
    }

    func deleteRule(id: UUID) {
        rules.removeAll { $0.id == id }
        if selectedRuleID == id {
            selectedRuleID = rules.first?.id
        }
        save()
    }

    // MARK: - Persistence

    func load() {
        guard FileManager.default.fileExists(atPath: storeURL.path),
              let data = try? Data(contentsOf: storeURL),
              let decoded = try? JSONDecoder().decode(PersistedShape.self, from: data)
        else { return }
        rules = decoded.rules
        selectedRuleID = decoded.selectedRuleID
    }

    func save() {
        let shape = PersistedShape(rules: rules, selectedRuleID: selectedRuleID)
        guard let data = try? JSONEncoder().encode(shape) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }

    // MARK: - Defaults

    static func makeDefaultRule() -> ExportPathRule {
        // Generic first rule. Tag category ids are placeholders and will be
        // resolved against the tag store on apply.
        ExportPathRule(
            name: "Camera / Date",
            components: [.cameraModel, .captureDate]
        )
    }
}
