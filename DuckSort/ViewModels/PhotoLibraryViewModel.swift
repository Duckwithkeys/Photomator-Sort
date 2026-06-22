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
    
    private var isInitializing = true
    
    // MARK: - Published state
    
    @Published private(set) var sourceDirectories: [URL] = []
    /// Individually imported files (via drag-and-drop or Import…) that live
    /// outside of a scanned source directory.
    @Published private(set) var looseFiles: [URL] = []
    @Published private(set) var failedSources: Set<URL> = []
    @Published private(set) var destinationDirectory: URL?
    @Published private(set) var photoSets: [PhotoSet] = [] {
        didSet {
            updateGlobalCounts()
            updateDerivedState()
        }
    }
    @Published private(set) var photoMetadata: [UUID: MetadataSnapshot] = [:]
    @Published var filterRule: PhotoFilterRule = .allPhotos {
        didSet {
            guard !isInitializing else { return }
            UserPreferences.shared.lastFilterRule = filterRule
            UserPreferences.shared.save()
            updateDerivedState()
        }
    }
    @Published var selectedTagFilters: Set<UUID> = [] {
        didSet {
            updateDerivedState()
        }
    }
    @Published var selectedFlags: Set<Int> = [] {
        didSet {
            updateDerivedState()
        }
    }
    @Published var selectedRatings: Set<Int> = [] {
        didSet {
            updateDerivedState()
        }
    }
    @Published var namingPreset: ExportNamingPreset = .dateOriginalSequence {
        didSet {
            guard !isInitializing else { return }
            UserPreferences.shared.lastNamingPreset = namingPreset
            UserPreferences.shared.save()
        }
    }
    @Published var jpegQuality: Double = 0.92 {
        didSet {
            guard !isInitializing else { return }
            UserPreferences.shared.lastJpegQuality = jpegQuality
            UserPreferences.shared.save()
        }
    }
    @Published var isJpegOnlyMode: Bool = false {
        didSet {
            guard !isInitializing else { return }
            UserPreferences.shared.isJpegOnlyMode = isJpegOnlyMode
            UserPreferences.shared.save()
            if !sourceDirectories.isEmpty {
                scanSourceDirectories(sourceDirectories)
            }
        }
    }
    @Published var isInspectorOpen: Bool = false {
        didSet {
            guard !isInitializing else { return }
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
            updateDerivedState()
        }
    }
    @Published var isLargeImageViewerOpen: Bool = false
    @Published var currentTagCategoryID: UUID? = nil

    /// Memoized counts & UI state
    @Published var searchText = "" {
        didSet {
            updateDerivedState()
        }
    }
    @Published var nearFocusedIds: Set<UUID> = []
    
    @Published var selectedSubfolderFilter: URL? = nil {
        didSet {
            updateDerivedState()
        }
    }
    @Published var cachedSubfolders: [URL: [URL]] = [:]
    @Published var cachedSubfolderCounts: [URL: Int] = [:]

    // Memoized sidebar counts
    var cachedAllPhotosCount: Int = 0
    var cachedEditedCount: Int = 0
    var cachedUneditedCount: Int = 0
    var cachedTagCounts: [UUID: Int] = [:]
    var cachedFlagCounts: [Int: Int] = [:]
    var cachedRatingCounts: [Int: Int] = [:]

    /// Number of columns the photo grid is currently rendering. Kept in sync by
    /// PhotoGridView so arrow-key navigation matches the visible layout.
    var gridColumnCount: Int = 1
    
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
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Init
    
    init(
        tagStore: TagStore? = nil,
        ruleStore: ExportRuleStore? = nil
    ) {
        self.tagStore = tagStore ?? TagStore()
        self.ruleStore = ruleStore ?? ExportRuleStore()
        
        self.tagStore.objectWillChange
            .sink { [weak self] _ in
                self?.updateGlobalCounts()
                self?.updateDerivedState()
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        
        self.filterRule = UserPreferences.shared.lastFilterRule
        self.namingPreset = UserPreferences.shared.lastNamingPreset
        self.jpegQuality = UserPreferences.shared.lastJpegQuality
        self.isJpegOnlyMode = UserPreferences.shared.isJpegOnlyMode
        self.isInspectorOpen = UserPreferences.shared.isInspectorOpen
        
        let urls = UserPreferences.shared.lastSourceDirectoryIDs.map { URL(fileURLWithPath: $0) }
        self.sourceDirectories = urls
        self.looseFiles = UserPreferences.shared.lastLooseFilePaths.map { URL(fileURLWithPath: $0) }

        if let destID = UserPreferences.shared.lastDestinationDirectoryID {
            self.destinationDirectory = URL(fileURLWithPath: destID)
        }

        self.tagManagerHotkey = UserPreferences.shared.tagManagerHotkey
        self.ruleEditorHotkey = UserPreferences.shared.ruleEditorHotkey
        self.openSourceHotkey = UserPreferences.shared.openSourceHotkey
        self.jpegOnlyHotkey = UserPreferences.shared.jpegOnlyHotkey
        
        self.isInitializing = false
        
        updateGlobalCounts()
        updateDerivedState()
        
        if !sourceDirectories.isEmpty || !looseFiles.isEmpty {
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
    
    @Published private(set) var filteredPhotoSets: [PhotoSet] = []
    
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
        guard let url = FolderPanel.chooseDirectory(title: "Add Source Folder") else { return }
        let standardized = url.standardizedFileURL
        if !sourceDirectories.contains(standardized) {
            var updated = sourceDirectories
            updated.append(standardized)
            sourceDirectories = updated
            persistSources()
            scanSourceDirectories(updated)
        }
    }

    /// Open a panel that accepts both files and folders, then import the result.
    func importItems() {
        let urls = FolderPanel.chooseItems(title: "Import Photos")
        guard !urls.isEmpty else { return }
        importURLs(urls)
    }

    /// Import a mix of dropped/selected files and folders. Folders become source
    /// directories (scanned recursively); files are grouped directly into sets.
    func importURLs(_ urls: [URL]) {
        let fm = FileManager.default
        var newDirs: [URL] = []
        var newFiles: [URL] = []

        for url in urls {
            let standardized = url.standardizedFileURL
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: standardized.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                newDirs.append(standardized)
            } else {
                newFiles.append(standardized)
            }
        }

        var dirs = sourceDirectories
        var files = looseFiles
        var changed = false

        for dir in newDirs where !dirs.contains(dir) {
            dirs.append(dir)
            changed = true
        }
        for file in newFiles where !files.contains(file) {
            files.append(file)
            changed = true
        }

        guard changed else { return }

        sourceDirectories = dirs
        looseFiles = files
        persistSources()
        scanSourceDirectories(dirs)
    }

    private func persistSources() {
        UserPreferences.shared.lastSourceDirectoryIDs = sourceDirectories.map(\.path)
        UserPreferences.shared.lastLooseFilePaths = looseFiles.map(\.path)
        UserPreferences.shared.save()
    }
    
    func removeSourceDirectory(_ url: URL) {
        let standardized = url.standardizedFileURL
        var updated = sourceDirectories
        updated.removeAll { $0.standardizedFileURL == standardized }
        sourceDirectories = updated
        persistSources()
        scanSourceDirectories(updated)
    }

    func removeLooseFile(_ url: URL) {
        let standardized = url.standardizedFileURL
        var updated = looseFiles
        updated.removeAll { $0.standardizedFileURL == standardized }
        looseFiles = updated
        persistSources()
        scanSourceDirectories(sourceDirectories)
    }

    func clearSourceDirectories() {
        sourceDirectories = []
        looseFiles = []
        photoSets = []
        photoMetadata = [:]
        persistSources()
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
        failedSources = []
        errorMessage = nil
        isScanning = true
        
        let looseFiles = self.looseFiles

        if urls.isEmpty && looseFiles.isEmpty {
            self.statusMessage = "No sources selected."
            self.isScanning = false
            return
        }

        let foldersText = urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) folders"
        statusMessage = urls.isEmpty
            ? "Scanning \(looseFiles.count) imported files..."
            : "Scanning \(foldersText) and subfolders..."

        scanTask = Task { @MainActor [scanner, isJpegOnlyMode] in
            var photoSets: [PhotoSet] = []
            var scannedFileCount = 0
            var failed: Set<URL> = []

            if !urls.isEmpty {
                let dirResult = await scanner.scanDirectories(urls, jpegOnly: isJpegOnlyMode)
                photoSets.append(contentsOf: dirResult.photoSets)
                scannedFileCount += dirResult.scannedFileCount
                failed.formUnion(dirResult.failedDirectories)
            }

            if !looseFiles.isEmpty {
                let fileResult = await scanner.scanFiles(looseFiles, jpegOnly: isJpegOnlyMode)
                photoSets.append(contentsOf: fileResult.photoSets)
                scannedFileCount += fileResult.scannedFileCount
                failed.formUnion(fileResult.failedDirectories)
            }

            photoSets.sort {
                $0.baseName.localizedStandardCompare($1.baseName) == .orderedAscending
            }

            self.photoSets = photoSets
            self.failedSources = failed
            let sourceLabel = urls.map(\.lastPathComponent).joined(separator: ", ")
            let scope = looseFiles.isEmpty ? sourceLabel
                : (urls.isEmpty ? "imported files" : "\(sourceLabel) + imported files")
            
            if failed.isEmpty {
                self.statusMessage = "Found \(photoSets.count) photo sets across [\(scope)], \(scannedFileCount) matching files."
            } else {
                self.statusMessage = "Found \(photoSets.count) photo sets, \(scannedFileCount) matching files. Warning: \(failed.count) source(s) failed to load."
            }
            
            self.loadExistingTags(for: photoSets)
            self.loadMetadata(for: photoSets)
            self.isScanning = false
        }
    }
    
    private func loadMetadata(for photoSets: [PhotoSet]) {
        metadataTask?.cancel()
        let sets = photoSets
        metadataTask = Task { @MainActor [metadataReader] in
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
                var updatedSets = self.photoSets
                for (id, snapshot) in cache {
                    if let idx = updatedSets.firstIndex(where: { $0.id == id }) {
                        if updatedSets[idx].rating == nil {
                            updatedSets[idx].rating = snapshot.rating
                        }
                        if updatedSets[idx].pick == nil {
                            updatedSets[idx].pick = snapshot.pick
                        }
                    }
                }
                self.photoSets = updatedSets
            }
        }
    }
    
    func toggleFlagFilter(_ flag: Int) {
        if selectedFlags.contains(flag) {
            selectedFlags.remove(flag)
        } else {
            selectedFlags.insert(flag)
        }
    }

    func toggleRatingFilter(_ rating: Int) {
        if selectedRatings.contains(rating) {
            selectedRatings.remove(rating)
        } else {
            selectedRatings.insert(rating)
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
    
    // MARK: - Permanent Tags (Rating & Pick)

    func setRating(_ rating: Int?, for id: PhotoSet.ID) {
        guard let index = photoSets.firstIndex(where: { $0.id == id }) else { return }
        photoSets[index].rating = rating
        let photo = photoSets[index]
        
        Task { [xmpTagging] in
            do {
                try await xmpTagging.updatePermanentTags(rating: rating, pick: photo.pick, for: photo)
            } catch {
                await MainActor.run { self.errorMessage = "Failed to write rating: \(error.localizedDescription)" }
            }
        }
    }

    func setPick(_ pick: Int?, for id: PhotoSet.ID) {
        guard let index = photoSets.firstIndex(where: { $0.id == id }) else { return }
        photoSets[index].pick = pick
        let photo = photoSets[index]
        
        Task { [xmpTagging] in
            do {
                try await xmpTagging.updatePermanentTags(rating: photo.rating, pick: pick, for: photo)
            } catch {
                await MainActor.run { self.errorMessage = "Failed to write pick flag: \(error.localizedDescription)" }
            }
        }
    }
    
    func selectVisiblePhotoSets() {
        let visibleIDs = Set(filteredPhotoSets.map(\.id))
        var updated = photoSets
        for index in updated.indices where visibleIDs.contains(updated[index].id) {
            updated[index].isSelected = true
        }
        self.photoSets = updated
    }
    
    func clearSelection() {
        var updated = photoSets
        for index in updated.indices {
            updated[index].isSelected = false
        }
        self.photoSets = updated
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
        
        let names = tagIDs.compactMap { tagStore.tag(id: $0)?.name }
        let nameSet = Set(names)
        let previousTask = tagTask
        tagTask = Task { @MainActor [xmpTagging] in
            _ = await previousTask?.result
            do {
                if remove {
                    try await xmpTagging.clear(for: photo)
                } else {
                    try await xmpTagging.applyTagNames(nameSet, to: photo)
                }
            } catch {
                self.errorMessage = error.localizedDescription
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
        tagTask = Task { @MainActor [xmpTagging] in
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
        let tagNameMap: [UUID: Set<String>] = Dictionary(
            uniqueKeysWithValues: selected.map { set in
                (set.id, Set(tagStore.assignedTags(for: set.id).map(\.name)))
            }
        )
        let plan = TransferPlan(
            operation: operation,
            destinationDirectory: destinationDirectory,
            photoSets: selected,
            tagNames: tagNameMap
        )
        let currentSources = sourceDirectories
        transferTask = Task { @MainActor [transferService, currentSources] in
            do {
                let summary = try await transferService.execute(plan) { progress in
                    Task { @MainActor in
                        self.operationProgress = progress
                        self.statusMessage = "\(operation.progressTitle) \(progress.displayText)"
                    }
                }
                self.statusMessage = "\(summary.operation.rawValue) complete: \(summary.fileCount) files to \(summary.destinationDirectory.lastPathComponent)."
                if summary.sidecarFailures > 0 {
                    self.statusMessage += " (\(summary.sidecarFailures) sidecar(s) could not be written)"
                }
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
        transferTask = Task { @MainActor [routedTransfer, currentSources] in
            do {
                let summary = try await routedTransfer.execute(
                    plan,
                    categoryNameProvider: categoryNameProvider
                ) { progress in
                    Task { @MainActor in
                        self.operationProgress = progress
                        self.statusMessage = "\(operation.progressTitle) \(progress.displayText)"
                    }
                }
                let foldersText = summary.foldersCreated == 1 ? "1 folder" : "\(summary.foldersCreated) folders"
                self.statusMessage = "\(operation.displayName) complete: \(summary.fileCount) files across \(foldersText) under \(summary.baseDestination.lastPathComponent)."
                if summary.sidecarFailures > 0 {
                    self.statusMessage += " (\(summary.sidecarFailures) sidecar(s) could not be written)"
                }
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
        let allTags = tagStore.tags
        tagTask = Task { @MainActor [xmpTagging, tagStore] in
            var batchTags: [UUID: Set<UUID>] = [:]
            var updatedSets = sets
            
            await withTaskGroup(of: (UUID, (tags: Set<String>, rating: Int?, pick: Int?))?.self) { group in
                var index = 0
                var activeTasks = 0
                
                while index < sets.count && activeTasks < 16 {
                    let photo = sets[index]
                    group.addTask {
                        if Task.isCancelled { return nil }
                        let data = await xmpTagging.readSidecarData(from: photo)
                        return (photo.id, data)
                    }
                    index += 1
                    activeTasks += 1
                }
                
                while activeTasks > 0 {
                    guard let result = await group.next() else { break }
                    activeTasks -= 1
                    
                    if Task.isCancelled { break }
                    
                    if let (id, data) = result {
                        if !data.tags.isEmpty {
                            let tagIDs = Set(allTags
                                .filter { data.tags.contains($0.name) }
                                .map(\.id))
                            if !tagIDs.isEmpty {
                                batchTags[id] = tagIDs
                            }
                        }
                        
                        if data.rating != nil || data.pick != nil {
                            if let idx = updatedSets.firstIndex(where: { $0.id == id }) {
                                if let r = data.rating { updatedSets[idx].rating = r }
                                if let p = data.pick { updatedSets[idx].pick = p }
                            }
                        }
                    }
                    
                    while index < sets.count && activeTasks < 16 {
                        let photo = sets[index]
                        activeTasks += 1
                        group.addTask {
                            if Task.isCancelled { return nil }
                            let data = await xmpTagging.readSidecarData(from: photo)
                            return (photo.id, data)
                        }
                        index += 1
                    }
                }
            }
            
            if !Task.isCancelled {
                if !batchTags.isEmpty {
                    tagStore.setTagsBatch(batchTags)
                }
                self.photoSets = updatedSets
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
            guard !isInitializing else { return }
            UserPreferences.shared.tagManagerHotkey = tagManagerHotkey ?? ""
            UserPreferences.shared.save()
        }
    }

    @Published var ruleEditorHotkey: String? = "cmd+r" {
        didSet {
            guard !isInitializing else { return }
            UserPreferences.shared.ruleEditorHotkey = ruleEditorHotkey ?? ""
            UserPreferences.shared.save()
        }
    }

    @Published var openSourceHotkey: String? = "cmd+o" {
        didSet {
            guard !isInitializing else { return }
            UserPreferences.shared.openSourceHotkey = openSourceHotkey ?? ""
            UserPreferences.shared.save()
        }
    }

    @Published var jpegOnlyHotkey: String? = "shift+cmd+q" {
        didSet {
            guard !isInitializing else { return }
            UserPreferences.shared.jpegOnlyHotkey = jpegOnlyHotkey ?? ""
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

    var jpegOnlyShortcutInfo: KeyboardShortcutInfo? {
        guard let hotkey = jpegOnlyHotkey, !hotkey.isEmpty else { return nil }
        return KeyboardShortcutInfo.parse(hotkey)
    }

    // MARK: - Count Memoization & Index Clamping
    
    func updateDerivedState() {
        var list = photoSets.filter { filterRule.matches($0) }
        if !selectedTagFilters.isEmpty {
            list = list.filter { !selectedTagFilters.isDisjoint(with: tagStore.assignedTagIDs(for: $0.id)) }
        }
        if !selectedFlags.isEmpty {
            list = list.filter { selectedFlags.contains($0.pick ?? 0) }
        }
        if !selectedRatings.isEmpty {
            list = list.filter {
                let ratingVal = $0.rating ?? 0
                return selectedRatings.contains(ratingVal)
            }
        }
        if let subfolderFilter = selectedSubfolderFilter {
            let standardSub = subfolderFilter.standardizedFileURL
            list = list.filter { photoSet in
                photoSet.mediaFiles.contains { fileURL in
                    fileURL.deletingLastPathComponent().standardizedFileURL == standardSub
                }
            }
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            list = list.filter { $0.baseName.lowercased().contains(query) }
        }
        
        self.filteredPhotoSets = list
        
        // Clamp focusedPhotoIndex first to valid range of filteredPhotoSets
        let clamped: Int
        if !list.isEmpty {
            clamped = max(0, min(focusedPhotoIndex, list.count - 1))
        } else {
            clamped = 0
        }
        
        if focusedPhotoIndex != clamped {
            focusedPhotoIndex = clamped
        }
        
        let index = clamped
        let start = max(0, index - 10)
        let end = min(list.count - 1, index + 10)
        var newSet = Set<UUID>()
        if !list.isEmpty && start <= end {
            for i in start...end {
                newSet.insert(list[i].id)
            }
        }
        self.nearFocusedIds = newSet
    }

    func updateGlobalCounts() {
        self.cachedAllPhotosCount = photoSets.count
        self.cachedEditedCount = photoSets.filter(\.hasEdit).count
        self.cachedUneditedCount = photoSets.count - cachedEditedCount
        
        var tagCounts: [UUID: Int] = [:]
        for tag in tagStore.tags {
            tagCounts[tag.id] = photoSets.filter { tagStore.assignedTagIDs(for: $0.id).contains(tag.id) }.count
        }
        self.cachedTagCounts = tagCounts
        
        var flagCounts: [Int: Int] = [:]
        flagCounts[1] = photoSets.filter { $0.pick == 1 }.count
        flagCounts[-1] = photoSets.filter { $0.pick == -1 }.count
        flagCounts[0] = photoSets.filter { ($0.pick ?? 0) == 0 }.count
        self.cachedFlagCounts = flagCounts
        
        var ratingCounts: [Int: Int] = [:]
        for rating in 0...5 {
            ratingCounts[rating] = photoSets.filter { ($0.rating ?? 0) == rating }.count
        }
        self.cachedRatingCounts = ratingCounts
        
        // Cache subfolders and counts
        var subfoldersMap: [URL: [URL]] = [:]
        var subfolderPhotoCounts: [URL: Int] = [:]
        
        for sourceURL in sourceDirectories {
            let standardizedSource = sourceURL.standardizedFileURL.path
            var subfoldersSet = Set<URL>()
            
            for set in photoSets {
                for file in set.mediaFiles {
                    let parentDir = file.deletingLastPathComponent().standardizedFileURL
                    let parentPath = parentDir.path
                    if parentPath.hasPrefix(standardizedSource) && parentPath != standardizedSource {
                        subfoldersSet.insert(parentDir)
                    }
                }
            }
            let sorted = subfoldersSet.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
            subfoldersMap[sourceURL] = sorted
        }
        self.cachedSubfolders = subfoldersMap
        
        for subfolders in subfoldersMap.values {
            for subfolder in subfolders {
                let standardSub = subfolder.standardizedFileURL
                let count = photoSets.filter { photoSet in
                    photoSet.mediaFiles.contains { fileURL in
                        fileURL.deletingLastPathComponent().standardizedFileURL == standardSub
                    }
                }.count
                subfolderPhotoCounts[subfolder] = count
            }
        }
        self.cachedSubfolderCounts = subfolderPhotoCounts
    }
    
    func relativePath(of subfolderURL: URL, relativeTo sourceURL: URL) -> String {
        let sourcePath = sourceURL.standardizedFileURL.path
        let subfolderPath = subfolderURL.standardizedFileURL.path
        if subfolderPath.hasPrefix(sourcePath) {
            let startIdx = subfolderPath.index(subfolderPath.startIndex, offsetBy: sourcePath.count)
            var rel = String(subfolderPath[startIdx...])
            if rel.hasPrefix("/") {
                rel.removeFirst()
            }
            return rel
        }
        return subfolderURL.lastPathComponent
    }
    
} // <---------- THIS BRACE CLOSES THE CLASS.
