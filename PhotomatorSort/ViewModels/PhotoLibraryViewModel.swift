//
//  PhotoLibraryViewModel.swift
//  PhotomatorSort
//
//  Main-actor state container. Owns the photo library, tag store, export
//  rule store, and the routed copy/move/export workflow. File-system work
//  runs through actors so scans and transfers never block SwiftUI updates.
//

import Combine
import Foundation
import SwiftUI
import AppKit

@MainActor
final class PhotoLibraryViewModel: ObservableObject {
    
    // MARK: - Stores
    
    let tagStore: TagStore
    let ruleStore: ExportRuleStore
    
    // MARK: - Published state
    
    @Published private(set) var sourceDirectories: [URL] = []
    @Published private(set) var destinationDirectory: URL?
    @Published private(set) var photoSets: [PhotoSet] = []
    @Published private(set) var photoMetadata: [UUID: MetadataSnapshot] = [:]
    @Published var filterRule: PhotoFilterRule = .allPhotos {
        didSet {
            UserPreferences.shared.lastFilterRule = filterRule
            UserPreferences.shared.save()
        }
    }
    @Published var namingPreset: ExportNamingPreset = .dateOriginalSequence {
        didSet {
            UserPreferences.shared.lastNamingPreset = namingPreset
            UserPreferences.shared.save()
        }
    }
    @Published var jpegQuality: Double = 0.92 {
        didSet {
            UserPreferences.shared.lastJpegQuality = jpegQuality
            UserPreferences.shared.save()
        }
    }
    @Published var isJpegOnlyMode: Bool = false {
        didSet {
            UserPreferences.shared.isJpegOnlyMode = isJpegOnlyMode
            UserPreferences.shared.save()
            if !sourceDirectories.isEmpty {
                scanSourceDirectories(sourceDirectories)
            }
        }
    }
    @Published var isInspectorOpen: Bool = false {
        didSet {
            UserPreferences.shared.isInspectorOpen = isInspectorOpen
            UserPreferences.shared.save()
        }
    }
    @Published private(set) var isScanning = false
    @Published private(set) var isTransferring = false
    @Published private(set) var operationProgress: FileOperationProgress?
    @Published private(set) var statusMessage = "Choose a photoshoot folder to begin."
    @Published var errorMessage: String?
    
    /// Large image viewer state
    @Published var focusedPhotoIndex: Int = 0 {
        didSet {
            preloadNeighbors(around: focusedPhotoIndex)
        }
    }
    @Published var isLargeImageViewerOpen: Bool = false
    @Published var currentTagCategoryID: UUID? = nil
    
    // MARK: - Services
    
    private let scanner = FileScanner()
    private let xmpTagging = XMPTaggingService()         // new custom tag keywords
    private let transferService = FileTransferService()
    private let jpegExportService = JPEGExportService()
    private let routedTransfer = RoutedTransferService()
    private let metadataReader = MetadataReader()
    private var scanTask: Task<Void, Never>?
    private var transferTask: Task<Void, Never>?
    private var tagTask: Task<Void, Never>?
    private var metadataTask: Task<Void, Never>?
    
    // MARK: - Init
    
    init(
        tagStore: TagStore? = nil,
        ruleStore: ExportRuleStore? = nil
    ) {
        self.tagStore = tagStore ?? TagStore()
        self.ruleStore = ruleStore ?? ExportRuleStore()
        
        UserPreferences.shared.load()
        self.filterRule = UserPreferences.shared.lastFilterRule
        self.namingPreset = UserPreferences.shared.lastNamingPreset
        self.jpegQuality = UserPreferences.shared.lastJpegQuality
        self.isJpegOnlyMode = UserPreferences.shared.isJpegOnlyMode
        self.isInspectorOpen = UserPreferences.shared.isInspectorOpen
        
        let urls = UserPreferences.shared.lastSourceDirectoryIDs.map { URL(fileURLWithPath: $0) }
        self.sourceDirectories = urls
        
        if let destID = UserPreferences.shared.lastDestinationDirectoryID {
            self.destinationDirectory = URL(fileURLWithPath: destID)
        }

        self.tagManagerHotkey = UserPreferences.shared.tagManagerHotkey
        self.ruleEditorHotkey = UserPreferences.shared.ruleEditorHotkey
        self.openSourceHotkey = UserPreferences.shared.openSourceHotkey
        
        if !sourceDirectories.isEmpty {
            Task { [weak self] in
                self?.scanSourceDirectories(urls)
            }
        }
    }
    
    deinit {
        scanTask?.cancel()
        transferTask?.cancel()
        tagTask?.cancel()
        metadataTask?.cancel()
        
        // Clean up keyboard monitor if registered
        if let keyboardMonitor = keyboardMonitor {
            NSEvent.removeMonitor(keyboardMonitor)
        }
    }
    
    // MARK: - Derived state
    
    var filteredPhotoSets: [PhotoSet] {
        photoSets.filter { filterRule.matches($0) }
    }
    
    var selectedPhotoSets: [PhotoSet] {
        photoSets.filter(\.isSelected)
    }
    
    var selectedCount: Int { selectedPhotoSets.count }
    
    var selectedFileCount: Int {
        selectedPhotoSets.reduce(0) { $0 + $1.allFiles.count }
    }
    
    var editedCount: Int { photoSets.filter(\.hasEdit).count }
    var uneditedCount: Int { photoSets.count - editedCount }
    
    var canTransfer: Bool {
        destinationDirectory != nil && !selectedPhotoSets.isEmpty && !isTransferring
    }
    
    var currentFocusedPhotoSet: PhotoSet? {
        let list = filteredPhotoSets
        guard !list.isEmpty else { return nil }
        let safe = max(0, min(focusedPhotoIndex, list.count - 1))
        return list[safe]
    }
    
    func metadata(for photoSet: PhotoSet) -> MetadataSnapshot {
        photoMetadata[photoSet.id] ?? MetadataSnapshot()
    }
    
    func assignedTags(for photoSet: PhotoSet) -> [CustomTag] {
        tagStore.assignedTags(for: photoSet.id)
    }
    
    func tags(in categoryID: UUID) -> [CustomTag] {
        tagStore.tags(in: categoryID)
    }
    
    // MARK: - Directory selection
    
    func addSourceDirectory() {
        guard let url = FolderPanel.chooseDirectory(title: "Add Photoshoot Folder") else { return }
        let standardized = url.standardizedFileURL
        if !sourceDirectories.contains(standardized) {
            var updated = sourceDirectories
            updated.append(standardized)
            sourceDirectories = updated
            UserPreferences.shared.lastSourceDirectoryIDs = updated.map(\.path)
            UserPreferences.shared.save()
            scanSourceDirectories(updated)
        }
    }
    
    func removeSourceDirectory(_ url: URL) {
        let standardized = url.standardizedFileURL
        var updated = sourceDirectories
        updated.removeAll { $0.standardizedFileURL == standardized }
        sourceDirectories = updated
        UserPreferences.shared.lastSourceDirectoryIDs = updated.map(\.path)
        UserPreferences.shared.save()
        scanSourceDirectories(updated)
    }
    
    func clearSourceDirectories() {
        sourceDirectories = []
        photoSets = []
        photoMetadata = [:]
        UserPreferences.shared.lastSourceDirectoryIDs = []
        UserPreferences.shared.save()
        statusMessage = "Choose a photoshoot folder to begin."
    }
    
    func chooseDestinationDirectory() {
        guard let url = FolderPanel.chooseDirectory(title: "Choose Destination Folder") else { return }
        UserPreferences.shared.lastDestinationDirectoryID = url.standardizedFileURL.path
        UserPreferences.shared.save()
        destinationDirectory = url
        statusMessage = "Destination set to \(url.lastPathComponent)."
    }
    
    // MARK: - Scan
    
    func scanSourceDirectories(_ urls: [URL]) {
        scanTask?.cancel()
        metadataTask?.cancel()
        sourceDirectories = urls
        photoSets = []
        photoMetadata = [:]
        errorMessage = nil
        isScanning = true
        
        if urls.isEmpty {
            self.statusMessage = "No source folders selected."
            self.isScanning = false
            return
        }
        
        let foldersText = urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) folders"
        statusMessage = "Scanning \(foldersText) and subfolders..."
        
        scanTask = Task { [scanner, isJpegOnlyMode] in
            do {
                let result = try await scanner.scanDirectories(urls, jpegOnly: isJpegOnlyMode)
                self.photoSets = result.photoSets
                let folderNames = urls.map(\.lastPathComponent).joined(separator: ", ")
                self.statusMessage = "Found \(result.photoSets.count) photo sets across [\(folderNames)], \(result.scannedFileCount) matching files."
                self.loadExistingTags(for: result.photoSets)
                self.loadMetadata(for: result.photoSets)
            } catch is CancellationError {
                self.statusMessage = "Scan cancelled."
            } catch {
                self.errorMessage = error.localizedDescription
                self.statusMessage = "Scan failed."
            }
            self.isScanning = false
        }
    }
    
    private func loadMetadata(for photoSets: [PhotoSet]) {
        metadataTask?.cancel()
        let sets = photoSets
        metadataTask = Task { [metadataReader] in
            var cache: [UUID: MetadataSnapshot] = [:]
            
            await withTaskGroup(of: (UUID, MetadataSnapshot)?.self) { group in
                var index = 0
                var activeTasks = 0
                
                // 1. Fill the buffer with up to 8 concurrent tasks
                while index < sets.count && activeTasks < 8 {
                    let set = sets[index]
                    index += 1
                    
                    guard let url = set.preferredPreviewURL else { continue }
                    
                    activeTasks += 1
                    group.addTask {
                        if Task.isCancelled { return nil }
                        let snapshot = metadataReader.metadata(for: url)
                        return (set.id, snapshot)
                    }
                }
                
                // 2. Process results and maintain up to 8 concurrent tasks
                while activeTasks > 0 {
                    guard let result = await group.next() else { break }
                    activeTasks -= 1
                    
                    if Task.isCancelled { break }
                    
                    if let (id, snapshot) = result {
                        cache[id] = snapshot
                    }
                    
                    // 3. Add new tasks to replace the completed ones
                    while index < sets.count && activeTasks < 8 {
                        let set = sets[index]
                        index += 1
                        
                        guard let url = set.preferredPreviewURL else { continue }
                        
                        activeTasks += 1
                        group.addTask {
                            if Task.isCancelled { return nil }
                            let snapshot = metadataReader.metadata(for: url)
                            return (set.id, snapshot)
                        }
                        break
                    }
                }
            }
            
            if !Task.isCancelled {
                self.photoMetadata = cache
            }
        }
    }
    
    // MARK: - Selection
    
    func toggleSelection(for id: PhotoSet.ID) {
        guard let index = photoSets.firstIndex(where: { $0.id == id }) else { return }
        photoSets[index].isSelected.toggle()
    }
    
    func setSelection(_ isSelected: Bool, for id: PhotoSet.ID) {
        guard let index = photoSets.firstIndex(where: { $0.id == id }) else { return }
        photoSets[index].isSelected = isSelected
    }
    
    func selectVisiblePhotoSets() {
        let visibleIDs = Set(filteredPhotoSets.map(\.id))
        for index in photoSets.indices where visibleIDs.contains(photoSets[index].id) {
            photoSets[index].isSelected = true
        }
    }
    
    func clearSelection() {
        for index in photoSets.indices {
            photoSets[index].isSelected = false
        }
    }
    
    // MARK: - Large image viewer navigation
    
    func openLargeImageViewer() {
        guard !filteredPhotoSets.isEmpty else {
            errorMessage = "Load a photoshoot before opening the viewer."
            return
        }
        let count = filteredPhotoSets.count
        if focusedPhotoIndex < 0 || focusedPhotoIndex >= count {
            focusedPhotoIndex = 0
        }
        isLargeImageViewerOpen = true
        currentTagCategoryID = tagStore.categories.first?.id
        statusMessage = "Viewer mode — use ←/→ to navigate, hotkeys to tag, Esc to close."
        preloadNeighbors(around: focusedPhotoIndex)
    }
    
    func closeLargeImageViewer() {
        isLargeImageViewerOpen = false
        statusMessage = "Exited viewer mode."
    }
    
    func navigateFocusedPhoto(delta: Int) {
        let count = filteredPhotoSets.count
        guard count > 0 else { return }
        focusedPhotoIndex = max(0, min(count - 1, focusedPhotoIndex + delta))
    }
    
    func preloadNeighbors(around index: Int) {
        let sets = filteredPhotoSets
        guard !sets.isEmpty else { return }
        
        let neighbors = [index - 1, index + 1, index + 2]
        for neighborIndex in neighbors {
            if neighborIndex >= 0 && neighborIndex < sets.count {
                LargeImageLoader.preload(url: sets[neighborIndex].preferredPreviewURL)
            }
        }
    }
    
    func cycleCurrentCategory(direction: Int) {
        guard !tagStore.categories.isEmpty else { return }
        
        let cats = tagStore.categories
        guard let index = cats.firstIndex(where: { $0.id == (currentTagCategoryID ?? UUID()) }) else {
            currentTagCategoryID = cats.first?.id
            return
        }
        let next = (index + direction + cats.count) % cats.count
        currentTagCategoryID = cats[next].id
    }
    
    // MARK: - Tag application (focused photo, no auto-advance)
    
    func applyTagToFocusedPhoto(_ tag: CustomTag) {
        guard let photo = currentFocusedPhotoSet else { return }
        var current = tagStore.assignedTagIDs(for: photo.id)
        let alreadyApplied = current.contains(tag.id)
        if !alreadyApplied {
            current.insert(tag.id)
            statusMessage = "Tagged \(photo.baseName) with \(tag.name)."
        } else {
            current.remove(tag.id)
            statusMessage = "Removed \(tag.name) from \(photo.baseName)."
        }
        commitTagChange(current, for: photo, remove: current.isEmpty)
    }
    
    func applyTag(_ tag: CustomTag, to photoSetID: UUID) {
        guard let photo = photoSets.first(where: { $0.id == photoSetID }) else { return }
        var current = tagStore.assignedTagIDs(for: photoSetID)
        let alreadyApplied = current.contains(tag.id)
        if !alreadyApplied { current.insert(tag.id) }
        commitTagChange(current, for: photo, remove: false)
    }
    
    func removeTag(_ tag: CustomTag, from photoSetID: UUID) {
        guard let photo = photoSets.first(where: { $0.id == photoSetID }) else { return }
        var current = tagStore.assignedTagIDs(for: photoSetID)
        current.remove(tag.id)
        commitTagChange(current, for: photo, remove: current.isEmpty)
    }
    
    func clearTags(for photoSetID: UUID) {
        guard let photo = photoSets.first(where: { $0.id == photoSetID }) else { return }
        commitTagChange([], for: photo, remove: true)
    }
    
    private func commitTagChange(_ tagIDs: Set<UUID>, for photo: PhotoSet, remove: Bool) {
        tagStore.setTags(tagIDs, for: photo.id)
        
        tagTask?.cancel()
        let names = tagIDs.compactMap { tagStore.tag(id: $0)?.name }
        let nameSet = Set(names)
        tagTask = Task { [xmpTagging] in
            do {
                if remove {
                    try await xmpTagging.clear(for: photo)
                } else {
                    try await xmpTagging.applyTagNames(nameSet, to: photo)
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    func clearTagsForSelection() {
        let selected = selectedPhotoSets
        guard !selected.isEmpty else {
            errorMessage = "Select at least one photo set before clearing tags."
            return
        }
        tagTask?.cancel()
        statusMessage = "Clearing tags for \(selected.count) selected photo sets..."
        tagTask = Task { [xmpTagging] in
            do {
                for photo in selected {
                    try Task.checkCancellation()
                    try await xmpTagging.clear(for: photo)
                }
                for photo in selected {
                    self.tagStore.clearTags(for: photo.id)
                }
                self.statusMessage = "Cleared tags for \(selected.count) photo sets."
            } catch is CancellationError {
                self.statusMessage = "Tag clearing cancelled."
            } catch {
                self.errorMessage = error.localizedDescription
                self.statusMessage = "Could not clear tags."
            }
        }
    }
    
    // MARK: - Plain transfer (no routing)
    
    func transferSelectedPhotoSets(operation: TransferOperation) {
        guard let destinationDirectory else { return }
        let selected = selectedPhotoSets
        guard !selected.isEmpty else {
            errorMessage = TransferError.noSelection.localizedDescription
            return
        }
        transferTask?.cancel()
        isTransferring = true
        operationProgress = nil
        errorMessage = nil
        statusMessage = "\(operation.progressTitle) \(selected.count) selected photo sets (\(selectedFileCount) files)..."
        let plan = TransferPlan(
            operation: operation,
            destinationDirectory: destinationDirectory,
            photoSets: selected
        )
        let currentSources = sourceDirectories
        transferTask = Task { [transferService, currentSources] in
            do {
                let summary = try await transferService.execute(plan) { progress in
                    await MainActor.run {
                        self.operationProgress = progress
                        self.statusMessage = "\(operation.progressTitle) \(progress.displayText)"
                    }
                }
                self.statusMessage = "\(summary.operation.rawValue) complete: \(summary.fileCount) files to \(summary.destinationDirectory.lastPathComponent)."
                self.clearSelection()
                if operation == .move {
                    self.scanSourceDirectories(currentSources)
                }
            } catch is CancellationError {
                self.statusMessage = "Transfer cancelled."
            } catch {
                self.errorMessage = error.localizedDescription
                self.statusMessage = "Transfer failed."
            }
            self.operationProgress = nil
            self.isTransferring = false
        }
    }
    
    // MARK: - Routed transfer (copy / move / export JPEG with rule)
    
    func performRoutedOperation(_ operation: RoutedOperation) {
        guard let destinationDirectory else {
            errorMessage = "Choose a destination folder first."
            return
        }
        let selected = selectedPhotoSets
        guard !selected.isEmpty else {
            errorMessage = TransferError.noSelection.localizedDescription
            return
        }
        guard let rule = ruleStore.selectedRule else {
            errorMessage = "Create an export routing rule first."
            return
        }
        
        let routedPhotos: [RoutedPhoto] = selected.map { photo in
            RoutedPhoto(
                photoSet: photo,
                metadata: photoMetadata[photo.id] ?? MetadataSnapshot(),
                tags: tagStore.assignedTags(for: photo.id)
            )
        }
        
        let plan = RoutedPlan(
            operation: operation,
            baseDestination: destinationDirectory,
            rule: rule.components,
            photos: routedPhotos,
            jpegQuality: jpegQuality,
            namingPreset: namingPreset
        )
        
        let categoryNames = Dictionary(
            uniqueKeysWithValues: tagStore.categories.map { ($0.id, $0.name) }
        )
        let categoryNameProvider: @Sendable (UUID) -> String? = { id in
            categoryNames[id]
        }
        
        transferTask?.cancel()
        isTransferring = true
        operationProgress = nil
        errorMessage = nil
        statusMessage = "\(operation.progressTitle) \(selected.count) photo sets into routed folders..."
        
        let currentSources = sourceDirectories
        transferTask = Task { [routedTransfer, currentSources] in
            do {
                let summary = try await routedTransfer.execute(
                    plan,
                    categoryNameProvider: categoryNameProvider
                ) { progress in
                    await MainActor.run {
                        self.operationProgress = progress
                        self.statusMessage = "\(operation.progressTitle) \(progress.displayText)"
                    }
                }
                let foldersText = summary.foldersCreated == 1 ? "1 folder" : "\(summary.foldersCreated) folders"
                self.statusMessage = "\(operation.displayName) complete: \(summary.fileCount) files across \(foldersText) under \(summary.baseDestination.lastPathComponent)."
                self.clearSelection()
                if operation == .moveOriginals {
                    self.scanSourceDirectories(currentSources)
                }
            } catch is CancellationError {
                self.statusMessage = "Operation cancelled."
            } catch {
                self.errorMessage = error.localizedDescription
                self.statusMessage = "Routed operation failed."
            }
            self.operationProgress = nil
            self.isTransferring = false
        }
    }
    
    // MARK: - Tag loading (legacy back-compat + custom)

    private func loadExistingTags(for photoSets: [PhotoSet]) {
        tagTask?.cancel()
        let sets = photoSets
        tagTask = Task { [xmpTagging, tagStore] in
            for photo in sets {
                try? Task.checkCancellation()
                let names = await xmpTagging.readTagNames(from: photo)
                guard !names.isEmpty else { continue }
                let tagIDs = Set(tagStore.tags
                    .filter { names.contains($0.name) }
                    .map(\.id))
                if !tagIDs.isEmpty {
                    await MainActor.run {
                        tagStore.setTags(tagIDs, for: photo.id)
                    }
                }
            }
        }
    }
    
    // MARK: - Keyboard Monitor Retention
    private var keyboardMonitor: Any? = nil

    func registerKeyboardMonitor(_ handler: @escaping (NSEvent) -> Bool) {
        if let existing = keyboardMonitor {
            NSEvent.removeMonitor(existing)
        }
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if handler(event) {
                return nil
            }
            return event
        }
    }

    @Published var tagManagerHotkey: String? = "cmd+t" {
        didSet {
            UserPreferences.shared.tagManagerHotkey = tagManagerHotkey ?? ""
            UserPreferences.shared.save()
        }
    }

    @Published var ruleEditorHotkey: String? = "cmd+r" {
        didSet {
            UserPreferences.shared.ruleEditorHotkey = ruleEditorHotkey ?? ""
            UserPreferences.shared.save()
        }
    }

    @Published var openSourceHotkey: String? = "cmd+o" {
        didSet {
            UserPreferences.shared.openSourceHotkey = openSourceHotkey ?? ""
            UserPreferences.shared.save()
        }
    }

    var tagManagerShortcutInfo: KeyboardShortcutInfo? {
        guard let hotkey = tagManagerHotkey, !hotkey.isEmpty else { return nil }
        return KeyboardShortcutInfo.parse(hotkey)
    }

    var ruleEditorShortcutInfo: KeyboardShortcutInfo? {
        guard let hotkey = ruleEditorHotkey, !hotkey.isEmpty else { return nil }
        return KeyboardShortcutInfo.parse(hotkey)
    }

    var openSourceShortcutInfo: KeyboardShortcutInfo? {
        guard let hotkey = openSourceHotkey, !hotkey.isEmpty else { return nil }
        return KeyboardShortcutInfo.parse(hotkey)
    }
    
} // <---------- THIS BRACE CLOSES THE CLASS.
