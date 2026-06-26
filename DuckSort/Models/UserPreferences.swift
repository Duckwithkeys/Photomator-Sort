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
    @Published var showAdvancedEXIF: Bool = false

    /// ID of the tag pack the user has most recently activated. Empty when
    /// the user has never picked a pack or has cleared all tags manually.
    @Published var activeTagPackID: String = TagPack.defaultPackID

    /// Set to true once the first-launch onboarding flow finishes. Re-runnable
    /// any time from the Help menu (Show Welcome Guide…).
    @Published var hasCompletedOnboarding: Bool = false

    @Published var tagManagerHotkey: String = "cmd+t"
    @Published var ruleEditorHotkey: String = "cmd+r"
    @Published var openSourceHotkey: String = "cmd+o"
    @Published var jpegOnlyHotkey: String = "shift+cmd+q"

    // MARK: - IPTC / Copyright Embedding
    //
    // When the master toggle is on, these values are embedded into every
    // XMP sidecar written by the export pipeline so downstream DAM tools,
    // Lightroom, Photomator, etc. pick up the photographer, rights, and
    // contact info automatically.

    @Published var embedIPTCInExports: Bool = false

    /// Photographer / creator name. Maps to `dc:creator` in the XMP packet.
    @Published var iptcCreatorName: String = ""

    /// Copyright line, e.g. "© 2026 Jane Doe". Maps to `dc:rights`.
    @Published var iptcCopyrightNotice: String = ""

    /// Email address. Maps to `Iptc4xmpCore:CiEmailWork`.
    @Published var iptcContactEmail: String = ""

    /// Phone number. Maps to `Iptc4xmpCore:CiTelWork`.
    @Published var iptcContactPhone: String = ""

    /// Website URL. Maps to `Iptc4xmpCore:CiUrlWork`.
    @Published var iptcContactWebsite: String = ""

    /// Free-text usage terms, e.g. "Licensed for editorial use only."
    /// Maps to `xmpRights:UsageTerms`.
    @Published var iptcRightsUsageTerms: String = ""

    private enum Keys {
        static let sourceList  = "lastSourceDirectories"
        static let looseFiles  = "lastLooseFiles"
        static let source      = "lastSourceDirectory" // for migration
        static let destination = "lastDestinationDirectory"
        static let filter      = "lastFilterRule"
        static let isJpegOnlyMode = "isJpegOnlyMode"
        static let isInspectorOpen = "isInspectorOpen"
        static let showAdvancedEXIF = "showAdvancedEXIF"
        static let activeTagPackID = "activeTagPackID"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let tagManagerHotkey = "tagManagerHotkey"
        static let ruleEditorHotkey = "ruleEditorHotkey"
        static let openSourceHotkey = "openSourceHotkey"
        static let jpegOnlyHotkey = "jpegOnlyHotkey"

        // IPTC / copyright
        static let embedIPTCInExports     = "embedIPTCInExports"
        static let iptcCreatorName        = "iptcCreatorName"
        static let iptcCopyrightNotice    = "iptcCopyrightNotice"
        static let iptcContactEmail       = "iptcContactEmail"
        static let iptcContactPhone       = "iptcContactPhone"
        static let iptcContactWebsite     = "iptcContactWebsite"
        static let iptcRightsUsageTerms   = "iptcRightsUsageTerms"
    }

    // MARK: - Persistence

    /// Debounced save. During initialization multiple properties fire
    /// `didSet` in quick succession; without debouncing, every property
    /// change would trigger a full UserDefaults flush.
    private var saveTask: Task<Void, Never>?

    func save() {
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000) // 150ms debounce
            guard !Task.isCancelled, let self else { return }
            self.performSave()
        }
    }

    /// Escape hatch for callers (e.g. user picks a folder) that need to
    /// flush immediately, bypassing the debounce window.
    func saveImmediately() {
        saveTask?.cancel()
        performSave()
    }

    private func performSave() {
        UserDefaults.standard.set(lastSourceDirectoryIDs, forKey: Keys.sourceList)
        UserDefaults.standard.set(lastLooseFilePaths, forKey: Keys.looseFiles)
        UserDefaults.standard.set(lastDestinationDirectoryID, forKey: Keys.destination)
        UserDefaults.standard.set(lastFilterRule.rawValue, forKey: Keys.filter)
        UserDefaults.standard.set(isJpegOnlyMode, forKey: Keys.isJpegOnlyMode)
        UserDefaults.standard.set(isInspectorOpen, forKey: Keys.isInspectorOpen)
        UserDefaults.standard.set(showAdvancedEXIF, forKey: Keys.showAdvancedEXIF)
        UserDefaults.standard.set(activeTagPackID, forKey: Keys.activeTagPackID)
        UserDefaults.standard.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding)
        UserDefaults.standard.set(tagManagerHotkey, forKey: Keys.tagManagerHotkey)
        UserDefaults.standard.set(ruleEditorHotkey, forKey: Keys.ruleEditorHotkey)
        UserDefaults.standard.set(openSourceHotkey, forKey: Keys.openSourceHotkey)
        UserDefaults.standard.set(jpegOnlyHotkey, forKey: Keys.jpegOnlyHotkey)

        UserDefaults.standard.set(embedIPTCInExports, forKey: Keys.embedIPTCInExports)
        UserDefaults.standard.set(iptcCreatorName, forKey: Keys.iptcCreatorName)
        UserDefaults.standard.set(iptcCopyrightNotice, forKey: Keys.iptcCopyrightNotice)
        UserDefaults.standard.set(iptcContactEmail, forKey: Keys.iptcContactEmail)
        UserDefaults.standard.set(iptcContactPhone, forKey: Keys.iptcContactPhone)
        UserDefaults.standard.set(iptcContactWebsite, forKey: Keys.iptcContactWebsite)
        UserDefaults.standard.set(iptcRightsUsageTerms, forKey: Keys.iptcRightsUsageTerms)
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
        showAdvancedEXIF = UserDefaults.standard.bool(forKey: Keys.showAdvancedEXIF)
        activeTagPackID = UserDefaults.standard.string(forKey: Keys.activeTagPackID) ?? TagPack.defaultPackID
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: Keys.hasCompletedOnboarding)

        tagManagerHotkey = UserDefaults.standard.string(forKey: Keys.tagManagerHotkey) ?? "cmd+t"
        ruleEditorHotkey = UserDefaults.standard.string(forKey: Keys.ruleEditorHotkey) ?? "cmd+r"
        openSourceHotkey = UserDefaults.standard.string(forKey: Keys.openSourceHotkey) ?? "cmd+o"
        jpegOnlyHotkey = UserDefaults.standard.string(forKey: Keys.jpegOnlyHotkey) ?? "shift+cmd+q"

        embedIPTCInExports = UserDefaults.standard.bool(forKey: Keys.embedIPTCInExports)
        iptcCreatorName = UserDefaults.standard.string(forKey: Keys.iptcCreatorName) ?? ""
        iptcCopyrightNotice = UserDefaults.standard.string(forKey: Keys.iptcCopyrightNotice) ?? ""
        iptcContactEmail = UserDefaults.standard.string(forKey: Keys.iptcContactEmail) ?? ""
        iptcContactPhone = UserDefaults.standard.string(forKey: Keys.iptcContactPhone) ?? ""
        iptcContactWebsite = UserDefaults.standard.string(forKey: Keys.iptcContactWebsite) ?? ""
        iptcRightsUsageTerms = UserDefaults.standard.string(forKey: Keys.iptcRightsUsageTerms) ?? ""
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: Keys.sourceList)
        UserDefaults.standard.removeObject(forKey: Keys.looseFiles)
        UserDefaults.standard.removeObject(forKey: Keys.source)
        UserDefaults.standard.removeObject(forKey: Keys.destination)
        UserDefaults.standard.removeObject(forKey: Keys.filter)
        UserDefaults.standard.removeObject(forKey: Keys.isJpegOnlyMode)
        UserDefaults.standard.removeObject(forKey: Keys.isInspectorOpen)
        UserDefaults.standard.removeObject(forKey: Keys.showAdvancedEXIF)
        UserDefaults.standard.removeObject(forKey: Keys.activeTagPackID)
        UserDefaults.standard.removeObject(forKey: Keys.hasCompletedOnboarding)
        UserDefaults.standard.removeObject(forKey: Keys.tagManagerHotkey)
        UserDefaults.standard.removeObject(forKey: Keys.ruleEditorHotkey)
        UserDefaults.standard.removeObject(forKey: Keys.openSourceHotkey)
        UserDefaults.standard.removeObject(forKey: Keys.jpegOnlyHotkey)

        UserDefaults.standard.removeObject(forKey: Keys.embedIPTCInExports)
        UserDefaults.standard.removeObject(forKey: Keys.iptcCreatorName)
        UserDefaults.standard.removeObject(forKey: Keys.iptcCopyrightNotice)
        UserDefaults.standard.removeObject(forKey: Keys.iptcContactEmail)
        UserDefaults.standard.removeObject(forKey: Keys.iptcContactPhone)
        UserDefaults.standard.removeObject(forKey: Keys.iptcContactWebsite)
        UserDefaults.standard.removeObject(forKey: Keys.iptcRightsUsageTerms)

        lastSourceDirectoryIDs = []
        lastLooseFilePaths = []
        lastDestinationDirectoryID = nil
        lastFilterRule = .allPhotos
        isJpegOnlyMode = false
        isInspectorOpen = false
        showAdvancedEXIF = false
        activeTagPackID = TagPack.defaultPackID
        hasCompletedOnboarding = false
        tagManagerHotkey = "cmd+t"
        ruleEditorHotkey = "cmd+r"
        openSourceHotkey = "cmd+o"
        jpegOnlyHotkey = "shift+cmd+q"

        embedIPTCInExports = false
        iptcCreatorName = ""
        iptcCopyrightNotice = ""
        iptcContactEmail = ""
        iptcContactPhone = ""
        iptcContactWebsite = ""
        iptcRightsUsageTerms = ""
    }
}