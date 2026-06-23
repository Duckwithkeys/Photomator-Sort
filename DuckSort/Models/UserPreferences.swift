//
//  UserPreferences.swift
//  PhotomatorSort
//
//  Kekeeps last-used source/destination folders and filter rule across launches.
//

import Foundation
import SwiftUI

@MainActor
final class UserPreferences: ObservableObject {
    static let shared = UserPreferences()
    
    private init() {
        load()
    }

    @Published var lastSourceDirectoryIDs: [String] = []
    @Published var lastLooseFilePaths: [String] = []
    @Published var lastDestinationDirectoryID: String?
    @Published var lastFilterRule: PhotoFilterRule = .allPhotos
    @Published var isJpegOnlyMode: Bool = false
    @Published var isInspectorOpen: Bool = false

    @Published var tagManagerHotkey: String = "cmd+t"
    @Published var ruleEditorHotkey: String = "cmd+r"
    @Published var openSourceHotkey: String = "cmd+o"
    @Published var jpegOnlyHotkey: String = "shift+cmd+q"

    private enum Keys {
        static let sourceList  = "lastSourceDirectories"
        static let looseFiles  = "lastLooseFiles"
        static let source      = "lastSourceDirectory" // for migration
        static let destination = "lastDestinationDirectory"
        static let filter      = "lastFilterRule"
        static let isJpegOnlyMode = "isJpegOnlyMode"
        static let isInspectorOpen = "isInspectorOpen"
        static let tagManagerHotkey = "tagManagerHotkey"
        static let ruleEditorHotkey = "ruleEditorHotkey"
        static let openSourceHotkey = "openSourceHotkey"
        static let jpegOnlyHotkey = "jpegOnlyHotkey"
    }

    // MARK: - Persistence

    func save() {
        UserDefaults.standard.set(lastSourceDirectoryIDs, forKey: Keys.sourceList)
        UserDefaults.standard.set(lastLooseFilePaths, forKey: Keys.looseFiles)
        UserDefaults.standard.set(lastDestinationDirectoryID, forKey: Keys.destination)
        UserDefaults.standard.set(lastFilterRule.rawValue, forKey: Keys.filter)
        UserDefaults.standard.set(isJpegOnlyMode, forKey: Keys.isJpegOnlyMode)
        UserDefaults.standard.set(isInspectorOpen, forKey: Keys.isInspectorOpen)
        UserDefaults.standard.set(tagManagerHotkey, forKey: Keys.tagManagerHotkey)
        UserDefaults.standard.set(ruleEditorHotkey, forKey: Keys.ruleEditorHotkey)
        UserDefaults.standard.set(openSourceHotkey, forKey: Keys.openSourceHotkey)
        UserDefaults.standard.set(jpegOnlyHotkey, forKey: Keys.jpegOnlyHotkey)
    }

    private func load() {
        lastSourceDirectoryIDs = UserDefaults.standard.stringArray(forKey: Keys.sourceList) ?? []
        // Migration:
        if lastSourceDirectoryIDs.isEmpty, let oldSource = UserDefaults.standard.string(forKey: Keys.source) {
            lastSourceDirectoryIDs = [oldSource]
        }
        
        lastLooseFilePaths = UserDefaults.standard.stringArray(forKey: Keys.looseFiles) ?? []

        lastDestinationDirectoryID = UserDefaults.standard.string(forKey: Keys.destination)

        if let raw = UserDefaults.standard.string(forKey: Keys.filter),
           let rule = PhotoFilterRule(rawValue: raw) {
            lastFilterRule = rule
        }

        isJpegOnlyMode = UserDefaults.standard.bool(forKey: Keys.isJpegOnlyMode)
        isInspectorOpen = UserDefaults.standard.bool(forKey: Keys.isInspectorOpen)

        tagManagerHotkey = UserDefaults.standard.string(forKey: Keys.tagManagerHotkey) ?? "cmd+t"
        ruleEditorHotkey = UserDefaults.standard.string(forKey: Keys.ruleEditorHotkey) ?? "cmd+r"
        openSourceHotkey = UserDefaults.standard.string(forKey: Keys.openSourceHotkey) ?? "cmd+o"
        jpegOnlyHotkey = UserDefaults.standard.string(forKey: Keys.jpegOnlyHotkey) ?? "shift+cmd+q"
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: Keys.sourceList)
        UserDefaults.standard.removeObject(forKey: Keys.looseFiles)
        UserDefaults.standard.removeObject(forKey: Keys.source)
        UserDefaults.standard.removeObject(forKey: Keys.destination)
        UserDefaults.standard.removeObject(forKey: Keys.filter)
        UserDefaults.standard.removeObject(forKey: Keys.isJpegOnlyMode)
        UserDefaults.standard.removeObject(forKey: Keys.isInspectorOpen)
        UserDefaults.standard.removeObject(forKey: Keys.tagManagerHotkey)
        UserDefaults.standard.removeObject(forKey: Keys.ruleEditorHotkey)
        UserDefaults.standard.removeObject(forKey: Keys.openSourceHotkey)
        UserDefaults.standard.removeObject(forKey: Keys.jpegOnlyHotkey)
        
        lastSourceDirectoryIDs = []
        lastLooseFilePaths = []
        lastDestinationDirectoryID = nil
        lastFilterRule = .allPhotos
        isJpegOnlyMode = false
        isInspectorOpen = false
        tagManagerHotkey = "cmd+t"
        ruleEditorHotkey = "cmd+r"
        openSourceHotkey = "cmd+o"
        jpegOnlyHotkey = "shift+cmd+q"
    }
}
