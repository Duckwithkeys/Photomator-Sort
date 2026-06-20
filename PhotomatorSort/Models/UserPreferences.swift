//
//  UserPreferences.swift
//  PhotomatorSort
//
//  Kekeeps last-used source/destination folders and filter rule across launches.
//

import Foundation
import SwiftUI

final class UserPreferences: ObservableObject {
    static let shared = UserPreferences()

    @Published var lastSourceDirectoryIDs: [String] = []
    @Published var lastDestinationDirectoryID: String?
    @Published var lastFilterRule: PhotoFilterRule = .allPhotos
    @Published var lastNamingPreset: ExportNamingPreset = .dateOriginalSequence
    @Published var lastJpegQuality: Double = 0.92
    @Published var isJpegOnlyMode: Bool = false
    @Published var isInspectorOpen: Bool = false

    @Published var tagManagerHotkey: String = "cmd+t"
    @Published var ruleEditorHotkey: String = "cmd+r"
    @Published var openSourceHotkey: String = "cmd+o"

    private enum Keys {
        static let sourceList  = "lastSourceDirectories"
        static let source      = "lastSourceDirectory" // for migration
        static let destination = "lastDestinationDirectory"
        static let filter      = "lastFilterRule"
        static let naming      = "lastNamingPreset"
        static let jpegQuality = "lastJpegQuality"
        static let isJpegOnlyMode = "isJpegOnlyMode"
        static let isInspectorOpen = "isInspectorOpen"
        static let tagManagerHotkey = "tagManagerHotkey"
        static let ruleEditorHotkey = "ruleEditorHotkey"
        static let openSourceHotkey = "openSourceHotkey"
    }

    // MARK: - Persistence

    func save() {
        UserDefaults.standard.set(lastSourceDirectoryIDs, forKey: Keys.sourceList)
        UserDefaults.standard.set(lastDestinationDirectoryID, forKey: Keys.destination)
        UserDefaults.standard.set(lastFilterRule.rawValue, forKey: Keys.filter)
        UserDefaults.standard.set(lastNamingPreset.rawValue, forKey: Keys.naming)
        UserDefaults.standard.set(lastJpegQuality, forKey: Keys.jpegQuality)
        UserDefaults.standard.set(isJpegOnlyMode, forKey: Keys.isJpegOnlyMode)
        UserDefaults.standard.set(isInspectorOpen, forKey: Keys.isInspectorOpen)
        UserDefaults.standard.set(tagManagerHotkey, forKey: Keys.tagManagerHotkey)
        UserDefaults.standard.set(ruleEditorHotkey, forKey: Keys.ruleEditorHotkey)
        UserDefaults.standard.set(openSourceHotkey, forKey: Keys.openSourceHotkey)
    }

    func load() {
        lastSourceDirectoryIDs = UserDefaults.standard.stringArray(forKey: Keys.sourceList) ?? []
        // Migration:
        if lastSourceDirectoryIDs.isEmpty, let oldSource = UserDefaults.standard.string(forKey: Keys.source) {
            lastSourceDirectoryIDs = [oldSource]
        }
        
        lastDestinationDirectoryID = UserDefaults.standard.string(forKey: Keys.destination)

        if let raw = UserDefaults.standard.string(forKey: Keys.filter),
           let rule = PhotoFilterRule(rawValue: raw) {
            lastFilterRule = rule
        }

        if let raw = UserDefaults.standard.string(forKey: Keys.naming),
           let preset = ExportNamingPreset(rawValue: raw) {
            lastNamingPreset = preset
        }

        if let val = UserDefaults.standard.object(forKey: Keys.jpegQuality) as? Double {
            lastJpegQuality = val
        }

        isJpegOnlyMode = UserDefaults.standard.bool(forKey: Keys.isJpegOnlyMode)
        isInspectorOpen = UserDefaults.standard.bool(forKey: Keys.isInspectorOpen)

        tagManagerHotkey = UserDefaults.standard.string(forKey: Keys.tagManagerHotkey) ?? "cmd+t"
        ruleEditorHotkey = UserDefaults.standard.string(forKey: Keys.ruleEditorHotkey) ?? "cmd+r"
        openSourceHotkey = UserDefaults.standard.string(forKey: Keys.openSourceHotkey) ?? "cmd+o"
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: Keys.sourceList)
        UserDefaults.standard.removeObject(forKey: Keys.source)
        UserDefaults.standard.removeObject(forKey: Keys.destination)
        UserDefaults.standard.removeObject(forKey: Keys.filter)
        UserDefaults.standard.removeObject(forKey: Keys.naming)
        UserDefaults.standard.removeObject(forKey: Keys.jpegQuality)
        UserDefaults.standard.removeObject(forKey: Keys.isJpegOnlyMode)
        UserDefaults.standard.removeObject(forKey: Keys.isInspectorOpen)
        UserDefaults.standard.removeObject(forKey: Keys.tagManagerHotkey)
        UserDefaults.standard.removeObject(forKey: Keys.ruleEditorHotkey)
        UserDefaults.standard.removeObject(forKey: Keys.openSourceHotkey)
        
        lastSourceDirectoryIDs = []
        lastDestinationDirectoryID = nil
        lastFilterRule = .allPhotos
        lastNamingPreset = .dateOriginalSequence
        lastJpegQuality = 0.92
        isJpegOnlyMode = false
        isInspectorOpen = false
        tagManagerHotkey = "cmd+t"
        ruleEditorHotkey = "cmd+r"
        openSourceHotkey = "cmd+o"
    }
}
