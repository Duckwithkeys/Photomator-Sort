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
import UniformTypeIdentifiers

@MainActor
final class PhotoLibraryViewModel: ObservableObject {
    
    // MARK: - Stores
    
    let tagStore: TagStore
    let ruleStore: ExportRuleStore
    let packLibrary: TagPackLibrary
    
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
            rebuildPhotoSetIndex()
            updateGlobalCounts()
            updateDerivedState()
        }
    }

    /// O(1) lookup of a photo set's index in `photoSets` by its ID. Rebuilt
    /// inside the `photoSets` didSet so it stays in sync with the published
    /// array. Every method that previously did `photoSets.firstIndex(where:)`
    /// should go through this index instead.
    private var photoSetIndex: [UUID: Int] = [:]

    private func rebuildPhotoSetIndex() {
        photoSetIndex = Dictionary(uniqueKeysWithValues: photoSets.enumerated().map { ($1.id, $0) })
    }
    @Published private(set) var photoMetadata: [UUID: MetadataSnapshot] = [:]
    @Published private(set) var photoCaptions: [UUID: String] = [:]
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
    @Published var searchText = ""
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
        ruleStore: ExportRuleStore? = nil,
        packLibrary: TagPackLibrary? = nil
    ) {
        self.tagStore = tagStore ?? TagStore()
        self.ruleStore = ruleStore ?? ExportRuleStore()
        self.packLibrary = packLibrary ?? TagPackLibrary()
        
        self.tagStore.objectWillChange
            // Coalesce multiple `objectWillChange` fires from a batch tag
            // operation into a single MainActor pass per runloop cycle.
            // Previously a batch setTagsBatch could trigger 4 separate
            // updateGlobalCounts + updateDerivedState cycles; dispatching
            // through Task hops onto MainActor asynchronously and folds
            // multiple notifications queued in the same runloop cycle.
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.updateGlobalCounts()
                    self.updateDerivedState()
                    self.objectWillChange.send()
                }
            }
            .store(in: &cancellables)

        // Every change to the live tag/category lists should snapshot back
        // into the active pack's saved state so the user's edits survive
        // switching packs and relaunching the app.
        self.tagStore.$tags
            .dropFirst()
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncActivePackFromStore()
            }
            .store(in: &cancellables)
        self.tagStore.$categories
            .dropFirst()
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncActivePackFromStore()
            }
            .store(in: &cancellables)
        
        $searchText
            .dropFirst()
            .removeDuplicates()
            .debounce(for: .milliseconds(120), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateDerivedState()
            }
            .store(in: &cancellables)
        
        self.filterRule = UserPreferences.shared.lastFilterRule

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

    /// O(1) read of the cached selection count. Updated inside
    /// `updateGlobalCounts()` so the per-frame toolbar and footer don't
    /// trigger an O(n) filter every body re-evaluation.
    var selectedCount: Int { cachedSelectedCount }

    /// O(1) read of the cached selected file count. Same caching strategy as
    /// `selectedCount`.
    var selectedFileCount: Int { cachedSelectedFileCount }

    private var cachedSelectedCount: Int = 0
    private var cachedSelectedFileCount: Int = 0

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
        var snapshot = photoMetadata[photoSet.id] ?? MetadataSnapshot()
        if let caption = photoCaptions[photoSet.id] {
            snapshot.caption = caption
        }
        return snapshot
    }

    func caption(for photoSet: PhotoSet) -> String? {
        photoCaptions[photoSet.id]
    }

    /// Write a caption (description) to the photo set's XMP sidecars and update
    /// the in-memory cache. Pass an empty/whitespace-only string to clear it.
    func setCaption(_ caption: String?, for photoSetID: UUID) {
        guard let photo = photoSets.first(where: { $0.id == photoSetID }) else { return }
        let trimmed = caption?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized: String? = (trimmed?.isEmpty ?? true) ? nil : trimmed
        let previous = photoCaptions[photoSetID]
        if previous == normalized { return }

        if normalized == nil {
            photoCaptions.removeValue(forKey: photoSetID)
        } else {
            photoCaptions[photoSetID] = normalized
        }

        tagTask = Task { @MainActor [xmpTagging] in
            do {
                try xmpTagging.updateCaption(normalized, for: photo)
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }

        updateDerivedState()
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
            
            self.loadMetadataAndTags(for: photoSets)
            self.isScanning = false
        }
    }
    
    private func loadMetadata(for photoSets: [PhotoSet]) {
        // Replaced by loadMetadataAndTags. Kept as an internal entry point so
        // other call sites still compile while we transition.
        metadataTask?.cancel()
        tagTask?.cancel()
        loadMetadataAndTags(for: photoSets)
    }

    /// Single-pass loader: reads EXIF + XMP for every photo in one task group,
    /// in two phases (visible ~100 first, then the rest), and applies all
    /// results in ONE `photoSets` assignment so `updateGlobalCounts` and
    /// `updateDerivedState` only fire twice instead of four times.
    private func loadMetadataAndTags(for photoSets: [PhotoSet]) {
        metadataTask?.cancel()
        tagTask?.cancel()

        let sets = photoSets
        let allTags = tagStore.tags
        let nameToID: [String: UUID] = Dictionary(
            allTags.map { ($0.name.lowercased(), $0.id) },
            uniquingKeysWith: { first, _ in first }
        )

        metadataTask = Task { @MainActor [metadataReader, xmpTagging] in
            // ----- Phase 1: visible-first (first 100) -----
            let firstBatch = Array(sets.prefix(100))
            let firstResults = await Self.loadBatchMetadataAndTags(
                firstBatch, metadataReader: metadataReader, xmpTagging: xmpTagging
            )
            if Task.isCancelled { return }
            self.applyMetadataAndTagResults(firstResults, nameToID: nameToID)

            // ----- Phase 2: the remaining sets -----
            let remaining = Array(sets.dropFirst(100))
            guard !remaining.isEmpty else { return }
            let restResults = await Self.loadBatchMetadataAndTags(
                remaining, metadataReader: metadataReader, xmpTagging: xmpTagging
            )
            if Task.isCancelled { return }
            self.applyMetadataAndTagResults(restResults, nameToID: nameToID)
        }
    }

    /// Read EXIF metadata + XMP sidecar for every photo in `batch` in parallel.
    /// One task per photo so each set's I/O runs concurrently.
    private static func loadBatchMetadataAndTags(
        _ batch: [PhotoSet],
        metadataReader: MetadataReader,
        xmpTagging: XMPTaggingService
    ) async -> [LoadedPhotoInfo] {
        await withTaskGroup(of: LoadedPhotoInfo.self) { group in
            for photo in batch {
                group.addTask {
                    let metadata: MetadataSnapshot
                    if let url = photo.preferredPreviewURL {
                        metadata = metadataReader.metadata(for: url)
                    } else {
                        metadata = MetadataSnapshot()
                    }
                    let sidecar = xmpTagging.readSidecarData(from: photo)
                    return LoadedPhotoInfo(
                        id: photo.id,
                        metadata: metadata,
                        sidecarTags: sidecar.tags,
                        sidecarRating: sidecar.rating,
                        sidecarPick: sidecar.pick,
                        sidecarDescription: sidecar.description
                    )
                }
            }
            var out: [LoadedPhotoInfo] = []
            out.reserveCapacity(batch.count)
            for await result in group { out.append(result) }
            return out
        }
    }

    /// Apply a batch of metadata + tag results to the published state in
    /// ONE `photoSets` assignment. Uses a local O(1) index so we never do
    /// a `firstIndex(where:)` scan inside the per-photo loop.
    private func applyMetadataAndTagResults(
        _ results: [LoadedPhotoInfo],
        nameToID: [String: UUID]
    ) {
        guard !results.isEmpty else { return }
        var metadataCache: [UUID: MetadataSnapshot] = [:]
        metadataCache.reserveCapacity(results.count)
        var batchTags: [UUID: Set<UUID>] = [:]
        var batchCaptions: [UUID: String] = [:]

        var updatedSets = self.photoSets
        let localIndex = Dictionary(uniqueKeysWithValues: updatedSets.enumerated().map { ($1.id, $0) })

        for info in results {
            metadataCache[info.id] = info.metadata

            if !info.sidecarTags.isEmpty {
                let tagIDs = Set(info.sidecarTags.compactMap { nameToID[$0.lowercased()] })
                if !tagIDs.isEmpty {
                    batchTags[info.id] = tagIDs
                }
            }

            if let description = info.sidecarDescription, !description.isEmpty {
                batchCaptions[info.id] = description
            }

            if let idx = localIndex[info.id] {
                // Prefer sidecar rating/pick over EXIF — the sidecar is what
                // the user's editor wrote last, EXIF is whatever the camera
                // baked in. Only fill in when the photo set doesn't already
                // have a value (preserves any in-memory user state).
                let rating = info.sidecarRating ?? info.metadata.rating
                let pick = info.sidecarPick ?? info.metadata.pick
                if updatedSets[idx].rating == nil, let rating {
                    updatedSets[idx].rating = rating
                }
                if updatedSets[idx].pick == nil, let pick {
                    updatedSets[idx].pick = pick
                }
            }
        }

        self.photoMetadata = metadataCache
        if !batchTags.isEmpty {
            tagStore.setTagsBatch(batchTags)
        }
        if !batchCaptions.isEmpty {
            for (id, caption) in batchCaptions {
                self.photoCaptions[id] = caption
            }
        }
        self.photoSets = updatedSets
    }

    /// Compact value type used by `loadMetadataAndTags` to ferry per-photo
    /// results out of the task group without depending on the sidecar tuple
    /// type alias.
    fileprivate struct LoadedPhotoInfo: Sendable {
        let id: UUID
        let metadata: MetadataSnapshot
        let sidecarTags: Set<String>
        let sidecarRating: Int?
        let sidecarPick: Int?
        let sidecarDescription: String?
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
    
    /// The photo set that the user last single-clicked (without shift). This
    /// is the anchor used for shift-click range selection and for showing the
    /// "active focus" highlight ring distinct from the broader selection.
    @Published var selectionAnchorID: PhotoSet.ID? = nil

    func toggleSelection(for id: PhotoSet.ID) {
        guard let index = photoSetIndex[id] else { return }
        photoSets[index].isSelected.toggle()
        // Every toggle updates the anchor to this cell so a subsequent
        // shift-click extends from it.
        selectionAnchorID = id
    }

    func setSelection(_ isSelected: Bool, for id: PhotoSet.ID) {
        guard let index = photoSetIndex[id] else { return }
        photoSets[index].isSelected = isSelected
    }

    /// Select every visible photo set between the anchor (or ``id`` if no
    /// anchor exists) and ``id``, inclusive. If the anchor is missing, the
    /// anchor is set to ``id`` and only that cell is selected.
    func selectRange(to id: PhotoSet.ID, additive: Bool = false) {
        let visibleIDs = filteredPhotoSets.map(\.id)
        guard let endIndex = visibleIDs.firstIndex(of: id) else {
            statusMessage = "Shift-click target not found in current view."
            return
        }

        let anchorID = selectionAnchorID ?? id
        guard let startIndex = visibleIDs.firstIndex(of: anchorID) else {
            // Anchor was lost (e.g., the anchor photo is filtered out).
            // Treat the current click as the new anchor.
            setSelection(true, for: id)
            selectionAnchorID = id
            statusMessage = "Set new selection anchor at \(filteredPhotoSets[endIndex].baseName)."
            return
        }

        let lower = min(startIndex, endIndex)
        let upper = max(startIndex, endIndex)
        let rangeIDs = Set(visibleIDs[lower...upper])

        if additive {
            // Build a new array with the range merged into the existing
            // selection in one assignment so the `photoSets` didSet fires
            // exactly once. Per-subscript mutation would call
            // updateDerivedState() once per photo — that's what produced
            // the beach-ball spinner on large libraries.
            var updated = photoSets
            for index in updated.indices where rangeIDs.contains(updated[index].id) {
                updated[index].isSelected = true
            }
            photoSets = updated
        } else {
            let replaced = photoSets.map { photoSet -> PhotoSet in
                var copy = photoSet
                copy.isSelected = rangeIDs.contains(photoSet.id)
                return copy
            }
            photoSets = replaced
        }

        let direction = startIndex < endIndex ? "forward" : "backward"
        statusMessage = "Selected \(rangeIDs.count) photo set\(rangeIDs.count == 1 ? "" : "s") in range (\(direction))."
    }

    /// Replace the entire selection with the given IDs in one batch update.
    func replaceSelection(with ids: [PhotoSet.ID]) {
        let idSet = Set(ids)
        photoSets = photoSets.map { photoSet in
            var copy = photoSet
            copy.isSelected = idSet.contains(photoSet.id)
            return copy
        }
    }

    /// Target photo sets for batch metadata operations: the current selection
    /// if non-empty, otherwise just the focused photo. Used so that pressing
    /// "1-5 / X / tag hotkey" applies to the user's selection automatically.
    var batchTargetPhotoSets: [PhotoSet] {
        let selected = selectedPhotoSets
        return selected.isEmpty ? (currentFocusedPhotoSet.map { [$0] } ?? []) : selected
    }
    
    // MARK: - Permanent Tags (Rating & Pick)

    func setRating(_ rating: Int?, for id: PhotoSet.ID) {
        setRating(rating, forIDs: [id])
    }

    /// Apply the same rating to every photo in ``ids``. Pass an empty array
    /// to no-op (used when no photo is in scope).
    func setRating(_ rating: Int?, forIDs ids: [PhotoSet.ID]) {
        guard !ids.isEmpty else { return }
        // Build an index once instead of doing O(n) firstIndex lookups inside
        // the loop — for a 5,000-photo library that turns 25M comparisons
        // into 5K.
        var indexByID: [PhotoSet.ID: Int] = [:]
        indexByID.reserveCapacity(photoSets.count)
        for (i, set) in photoSets.enumerated() {
            indexByID[set.id] = i
        }
        var updated = photoSets
        var targets: [PhotoSet] = []
        for id in ids {
            if let index = indexByID[id] {
                updated[index].rating = rating
                targets.append(updated[index])
            }
        }
        photoSets = updated

        if let rating {
            statusMessage = "Rated \(ids.count) photo set\(ids.count == 1 ? "" : "s") ★\(rating)."
        } else {
            statusMessage = "Cleared rating on \(ids.count) photo set\(ids.count == 1 ? "" : "s")."
        }

        Task { [xmpTagging] in
            for photo in targets {
                do {
                    try xmpTagging.updatePermanentTags(rating: rating, pick: photo.pick, for: photo)
                } catch {
                    await MainActor.run { self.errorMessage = "Failed to write rating: \(error.localizedDescription)" }
                    return
                }
            }
        }
    }

    func setPick(_ pick: Int?, for id: PhotoSet.ID) {
        setPick(pick, forIDs: [id])
    }

    /// Apply the same pick flag to every photo in ``ids``.
    func setPick(_ pick: Int?, forIDs ids: [PhotoSet.ID]) {
        guard !ids.isEmpty else { return }
        var indexByID: [PhotoSet.ID: Int] = [:]
        indexByID.reserveCapacity(photoSets.count)
        for (i, set) in photoSets.enumerated() {
            indexByID[set.id] = i
        }
        var updated = photoSets
        var targets: [PhotoSet] = []
        for id in ids {
            if let index = indexByID[id] {
                updated[index].pick = pick
                targets.append(updated[index])
            }
        }
        photoSets = updated

        if let pick {
            statusMessage = "Set pick flag (\(pick)) on \(ids.count) photo set\(ids.count == 1 ? "" : "s")."
        } else {
            statusMessage = "Cleared pick flag on \(ids.count) photo set\(ids.count == 1 ? "" : "s")."
        }

        Task { [xmpTagging] in
            for photo in targets {
                do {
                    try xmpTagging.updatePermanentTags(rating: photo.rating, pick: pick, for: photo)
                } catch {
                    await MainActor.run { self.errorMessage = "Failed to write pick flag: \(error.localizedDescription)" }
                    return
                }
            }
        }
    }

    /// Clear pick flag on every photo in the current selection (or focused
    /// photo if nothing is selected). Bound to the "U" hotkey.
    func clearPickFlagOnSelection() {
        let ids = batchTargetPhotoSets.map(\.id)
        guard !ids.isEmpty else { return }
        setPick(0, forIDs: ids)
    }

    /// Reject the given photo and, if it is the currently focused one,
    /// advance ``focusedPhotoIndex`` to the next visible photo so culling
    /// flows continue smoothly. Rejected photos are filtered out of the
    /// default view (see ``updateDerivedState``) and only reappear when
    /// the user selects the "Rejected" filter in the sidebar.
    func rejectAndAdvance(for id: PhotoSet.ID) {
        // Snapshot the visible position *before* mutating pick, because
        // setPick triggers updateDerivedState, which removes rejected
        // photos from filteredPhotoSets.
        let priorIndex = filteredPhotoSets.firstIndex(where: { $0.id == id })

        setPick(-1, for: id)

        guard !filteredPhotoSets.isEmpty else { return }
        guard let currentIndex = priorIndex else { return }
        // The rejected photo is now hidden, so the photo at the same
        // index in the refreshed list is the next visible one.
        if currentIndex < filteredPhotoSets.count {
            focusedPhotoIndex = currentIndex
        } else {
            focusedPhotoIndex = filteredPhotoSets.count - 1
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
        self.selectionAnchorID = nil
    }

    // MARK: - Tag pack management

    /// Snapshot the currently-active tags into the outgoing pack's saved
    /// state, then load the incoming pack's state into the live tag
    /// store. Each pack has its own persistent state, so the user can
    /// edit Wedding, switch to Cars, then come back to Wedding and find
    /// their edits.
    func switchTagPack(id: String) {
        let incomingID = id
        let outgoingID = packLibrary.activePackID

        if incomingID == outgoingID { return }

        if let outgoing = packLibrary.state(for: outgoingID) {
            packLibrary.snapshotActivePack(from: tagStore, packID: outgoing.id)
            _ = outgoing
        }

        packLibrary.activePackID = incomingID
        packLibrary.applyPack(incomingID, to: tagStore)

        if let pack = packLibrary.state(for: incomingID) {
            statusMessage = "Switched to \(pack.name) tag pack."
        }
    }

    func switchTagPack(_ template: TagPackTemplate) {
        switchTagPack(id: template.id)
    }

    /// The currently active tag pack state. Falls back to the default
    /// template's factory state if the persisted id is unknown.
    var activeTagPack: TagPackState {
        packLibrary.activePack
    }

    // MARK: - Custom pack management (UI-facing wrappers)

    /// Create a new user pack. If `basedOnTemplateID` is provided, the
    /// new pack starts with that template's categories and tags. Otherwise
    /// it starts empty.
    @discardableResult
    func createPack(named name: String,
                    basedOnTemplateID: String? = nil,
                    copyFromPackID: String? = nil,
                    systemImage: String? = nil,
                    accentColor: String? = nil) -> TagPackState? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let newID = makeUniquePackID(basedOn: trimmed)

        var state: TagPackState
        if let fromID = copyFromPackID, let original = packLibrary.state(for: fromID) {
            state = TagPackState(
                id: newID,
                name: trimmed,
                tagline: original.tagline,
                systemImage: systemImage ?? original.systemImage,
                accentColor: accentColor ?? original.accentColor,
                isBuiltIn: false,
                categories: original.categories,
                tags: original.tags
            )
        } else if let templateID = basedOnTemplateID,
                  let template = TagPackTemplate.template(id: templateID) {
            state = TagPackState(
                id: newID,
                name: trimmed,
                tagline: template.tagline,
                systemImage: systemImage ?? template.systemImage,
                accentColor: accentColor ?? template.accentColor,
                isBuiltIn: false,
                categories: template.categories.map { TagPackState.CategoryEntry(name: $0) },
                tags: template.tags.map {
                    TagPackState.TagEntry(category: $0.category, name: $0.name,
                                          hotkey: $0.hotkey, colorHex: $0.colorHex)
                }
            )
        } else {
            state = TagPackState.empty(id: newID, name: trimmed)
            if systemImage != nil || accentColor != nil {
                state.systemImage = systemImage ?? state.systemImage
                state.accentColor = accentColor ?? state.accentColor
            }
        }
        packLibrary.upsert(state)
        return state
    }

    func renamePack(id: String, to newName: String) {
        packLibrary.renamePack(id: id, to: newName)
    }

    func restylePack(id: String, systemImage: String, accentColor: String) {
        packLibrary.restylePack(id: id, systemImage: systemImage, accentColor: accentColor)
    }

    // MARK: - XMP vs active pack diff

    /// Snapshot of tags that live in XMP sidecars but aren't defined in the
    /// currently active pack. Used by the View menu overlay so the user can
    /// see which keywords are being silently ignored.
    struct XMPTagDiff: Equatable {
        var activePackName: String
        /// Tags present in at least one XMP sidecar but absent from the active pack.
        var orphanTags: [String]
        /// `photoSetID → tag names` for each orphan tag (so the overlay can
        /// show which photos are affected).
        var orphanUsage: [UUID: [String]]
        var totalPhotosScanned: Int
    }

    /// Scan every loaded photo set's XMP sidecars and produce a diff against
    /// the active pack's known tag names. Returns an empty diff if there is
    /// no active pack, or if no XMP sidecars exist.
    func computeXMPTagDiff() async -> XMPTagDiff {
        let activePack = packLibrary.activePack
        let activePackName = activePack.name
        let knownNames = Set(tagStore.tags.map { $0.name.lowercased() })

        let sets = self.photoSets
        let total = sets.count

        return await Task.detached(priority: .userInitiated) { () -> XMPTagDiff in
            let service = XMPTaggingService()
            var usage: [String: [UUID]] = [:]
            var seenInXMP: Set<String> = []
            for set in sets {
                let (xmpTags, _, _, _) = service.readSidecarData(from: set)
                for raw in xmpTags {
                    let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !key.isEmpty else { continue }
                    seenInXMP.insert(key)
                    if !knownNames.contains(key.lowercased()) {
                        usage[key, default: []].append(set.id)
                    }
                }
            }
            let orphans = seenInXMP
                .filter { !knownNames.contains($0.lowercased()) }
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            var bySet: [UUID: [String]] = [:]
            for (name, ids) in usage {
                for id in ids {
                    bySet[id, default: []].append(name)
                }
            }
            return XMPTagDiff(
                activePackName: activePackName,
                orphanTags: orphans,
                orphanUsage: bySet,
                totalPhotosScanned: total
            )
        }.value
    }

    func resetPack(id: String) {
        // Snapshot the current edits first so the user doesn't lose work
        // for the *other* packs they might want to revisit.
        if id == packLibrary.activePackID {
            packLibrary.snapshotActivePack(from: tagStore, packID: id)
        }
        packLibrary.resetPack(id: id)
        if id == packLibrary.activePackID {
            packLibrary.applyPack(id, to: tagStore)
        }
        statusMessage = "Reset \(packLibrary.state(for: id)?.name ?? id)."
    }

    func duplicatePack(id: String, newName: String) -> TagPackState? {
        packLibrary.duplicatePack(id: id, newName: newName)
    }

    func deletePack(id: String) {
        guard !packLibrary.isBuiltIn(id) else { return }
        // If the user deletes the active pack, switch to the default first
        // so we always have something loaded.
        if id == packLibrary.activePackID {
            let fallback = TagPackTemplate.defaultTemplateID
            packLibrary.snapshotActivePack(from: tagStore, packID: id)
            packLibrary.activePackID = fallback
            packLibrary.applyPack(fallback, to: tagStore)
        }
        packLibrary.deletePack(id: id)
    }

    /// Persist the user's current edits to the tags into the active pack's
    /// saved state. Called automatically after tag/category mutations when
    /// the live tags differ from the last snapshot.
    func syncActivePackFromStore() {
        let id = packLibrary.activePackID
        packLibrary.snapshotActivePack(from: tagStore, packID: id)
    }

    // MARK: - Import / Export

    /// Prompt the user for a destination file and write the pack as a
    /// JSON document the user can share or back up.
    func exportPack(id: String) {
        guard let state = packLibrary.state(for: id) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.tagPack]
        panel.nameFieldStringValue = "\(state.name).tagpack.json"
        panel.canCreateDirectories = true
        panel.title = "Export Tag Pack"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try state.encodedForExport().write(to: url, options: .atomic)
            statusMessage = "Exported \(state.name) to \(url.lastPathComponent)."
        } catch {
            self.errorMessage = "Couldn't export pack: \(error.localizedDescription)"
        }
    }

    /// Prompt the user for a `.tagpack.json` file and add it as a new
    /// user pack.
    func importPack() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.tagPack]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "Import Tag Pack"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let incoming = try TagPackState.decodedFromImport(data)
            let stored = packLibrary.importPack(incoming)
            statusMessage = "Imported \(stored.name)."
        } catch {
            self.errorMessage = "Couldn't import pack: \(error.localizedDescription)"
        }
    }

    // MARK: - Helpers

    private func makeUniquePackID(basedOn name: String) -> String {
        let slug = name
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let base = slug.isEmpty ? "pack" : slug
        var candidate = "user-" + base
        var counter = 2
        while packLibrary.packs.contains(where: { $0.id == candidate }) {
            candidate = "user-\(base)-\(counter)"
            counter += 1
        }
        return candidate
    }

    // MARK: - Sidebar filter state

    @Published var isSidebarHidden: Bool = false

    var activeFilterCount: Int {
        selectedTagFilters.count
            + selectedFlags.count
            + selectedRatings.count
            + (selectedSubfolderFilter == nil ? 0 : 1)
    }

    func clearAllFilters() {
        selectedTagFilters.removeAll()
        selectedFlags.removeAll()
        selectedRatings.removeAll()
        selectedSubfolderFilter = nil
        searchText = ""
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
        applyTag(tag, toPhotoSets: [photo])
    }

    /// Apply a tag to one or more photo sets with selection-aware toggle
    /// semantics: if any photo in ``photos`` lacks the tag, it is added to
    /// every photo that lacks it; if all photos already have the tag, it is
    /// removed from every photo.
    func applyTag(_ tag: CustomTag, toPhotoSets photos: [PhotoSet]) {
        guard !photos.isEmpty else { return }
        let tagID = tag.id

        // Snapshot whether each target already has the tag, then mutate the
        // store synchronously in one pass so we don't repeatedly hit
        // tagStore.assignedTagIDs(for:) inside a hot loop.
        var targets: [(photo: PhotoSet, hasTag: Bool)] = []
        targets.reserveCapacity(photos.count)
        var anyMissing = false
        for photo in photos {
            let hasTag = tagStore.assignedTagIDs(for: photo.id).contains(tagID)
            if !hasTag { anyMissing = true }
            targets.append((photo, hasTag))
        }

        if anyMissing {
            for entry in targets where !entry.hasTag {
                let current = tagStore.assignedTagIDs(for: entry.photo.id)
                commitTagChange(current.union([tagID]),
                                for: entry.photo,
                                remove: false)
            }
            statusMessage = "Applied \(tag.name) to \(photos.count) photo set\(photos.count == 1 ? "" : "s")."
        } else {
            for entry in targets {
                let current = tagStore.assignedTagIDs(for: entry.photo.id).subtracting([tagID])
                commitTagChange(current,
                                for: entry.photo,
                                remove: current.isEmpty)
            }
            if photos.count == 1 {
                statusMessage = "Removed \(tag.name) from \(photos[0].baseName)."
            } else {
                statusMessage = "Removed \(tag.name) from \(photos.count) photo sets."
            }
        }
    }

    /// Apply a tag to every photo in the current selection (or focused photo
    /// if nothing is selected). Used by tag hotkeys.
    func applyTagToSelection(_ tag: CustomTag) {
        let targets = batchTargetPhotoSets
        applyTag(tag, toPhotoSets: targets)
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
        clearTags(forIDs: [photoSetID])
    }

    /// Clear custom tags for every photo in ``ids``. Used by the "0" hotkey
    /// so users can reset all tags on the selection in a single action.
    func clearTags(forIDs ids: [PhotoSet.ID]) {
        guard !ids.isEmpty else { return }
        let targets: [PhotoSet] = photoSets.filter { ids.contains($0.id) }
        for photo in targets {
            commitTagChange([], for: photo, remove: true)
        }
        statusMessage = "Cleared tags on \(ids.count) photo set\(ids.count == 1 ? "" : "s")."
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
                    try xmpTagging.clear(for: photo)
                } else {
                    try xmpTagging.applyTagNames(nameSet, to: photo)
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
                    try xmpTagging.clear(for: photo)
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
            tagNames: tagNameMap,
            metadata: photoMetadata
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
            photos: routedPhotos
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
    
    // MARK: - Tag loading (now merged into loadMetadataAndTags)

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
        // Hoist all "is this filter active" booleans and any precomputed
        // values out of the per-photo loop so the inner loop is one tight
        // sequence of continue/append operations.
        let hasTagFilter = !selectedTagFilters.isEmpty
        let hasFlagFilter = !selectedFlags.isEmpty
        let showRejected = selectedFlags.contains(-1)
        let hasRatingFilter = !selectedRatings.isEmpty
        let subfolderPath = selectedSubfolderFilter?.standardizedFileURL.path
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let hasSearchQuery = !query.isEmpty

        var list: [PhotoSet] = []
        list.reserveCapacity(photoSets.count)

        for photoSet in photoSets {
            // Filter rule (the main "library" view selector: All Photos,
            // Edited, Unedited, etc.)
            guard filterRule.matches(photoSet) else { continue }

            // Rejected photos are hidden from the default view; they only
            // reappear when the user explicitly activates the "Rejected"
            // filter (selectedFlags contains -1).
            if !showRejected && photoSet.pick == -1 { continue }

            // Tag filter
            if hasTagFilter {
                let assigned = tagStore.assignedTagIDs(for: photoSet.id)
                if selectedTagFilters.isDisjoint(with: assigned) { continue }
            }

            // Flag filter
            if hasFlagFilter {
                if !selectedFlags.contains(photoSet.pick ?? 0) { continue }
            }

            // Rating filter
            if hasRatingFilter {
                if !selectedRatings.contains(photoSet.rating ?? 0) { continue }
            }

            // Subfolder filter — compare .path strings to avoid URL resolution
            // on every file on every filter pass.
            if let subfolderPath {
                let matches = photoSet.mediaFiles.contains { fileURL in
                    fileURL.deletingLastPathComponent().path == subfolderPath
                }
                if !matches { continue }
            }

            // Search filter (baseName OR cached caption)
            if hasSearchQuery {
                if !photoSet.baseName.lowercased().contains(query),
                   !(photoCaptions[photoSet.id]?.lowercased().contains(query) ?? false) {
                    continue
                }
            }

            list.append(photoSet)
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
        newSet.reserveCapacity(end - start + 1)
        if !list.isEmpty && start <= end {
            for i in start...end {
                newSet.insert(list[i].id)
            }
        }
        self.nearFocusedIds = newSet
    }

    func updateGlobalCounts() {
        let totalPhotos = photoSets.count
        self.cachedAllPhotosCount = totalPhotos

        var editedCount = 0
        var pick1Count = 0
        var pickMinus1Count = 0
        var pick0Count = 0
        var ratingCounts = [Int: Int]()
        for r in 0...5 { ratingCounts[r] = 0 }

        var tagHistogram = [UUID: Int]()
        for tag in tagStore.tags { tagHistogram[tag.id] = 0 }

        var photoSetsBySubfolder = [URL: Set<UUID>]()

        // Reset selection counters before the loop so they stay consistent
        // with `photoSets` even when individual sets flip isSelected mid-loop
        // (which they don't, but the invariant is easier to reason about).
        cachedSelectedCount = 0
        cachedSelectedFileCount = 0

        for photoSet in photoSets {
            if photoSet.hasEdit {
                editedCount += 1
            }

            if photoSet.isSelected {
                cachedSelectedCount += 1
                cachedSelectedFileCount += photoSet.mediaFiles.count + (photoSet.editPath != nil ? 1 : 0)
            }
            
            let pick = photoSet.pick ?? 0
            if pick == 1 {
                pick1Count += 1
            } else if pick == -1 {
                pickMinus1Count += 1
            } else {
                pick0Count += 1
            }
            
            let rating = photoSet.rating ?? 0
            if rating >= 0 && rating <= 5 {
                ratingCounts[rating, default: 0] += 1
            }
            
            let assignedIDs = tagStore.assignedTagIDs(for: photoSet.id)
            for tagID in assignedIDs {
                tagHistogram[tagID, default: 0] += 1
            }
            
            for file in photoSet.mediaFiles {
                let parentDir = file.deletingLastPathComponent().standardizedFileURL
                photoSetsBySubfolder[parentDir, default: []].insert(photoSet.id)
            }
        }
        
        self.cachedEditedCount = editedCount
        self.cachedUneditedCount = totalPhotos - editedCount
        
        self.cachedTagCounts = tagHistogram
        self.cachedFlagCounts = [1: pick1Count, -1: pickMinus1Count, 0: pick0Count]
        self.cachedRatingCounts = ratingCounts
        
        var subfoldersMap: [URL: [URL]] = [:]
        var subfolderPhotoCounts: [URL: Int] = [:]
        
        let allSubfolders = Array(photoSetsBySubfolder.keys)
        
        for sourceURL in sourceDirectories {
            let standardizedSource = sourceURL.standardizedFileURL.path
            var subfoldersSet = Set<URL>()
            
            for parentDir in allSubfolders {
                let parentPath = parentDir.path
                if parentPath.hasPrefix(standardizedSource) && parentPath != standardizedSource {
                    subfoldersSet.insert(parentDir)
                }
            }
            
            let sorted = subfoldersSet.sorted { $0.path < $1.path }
            subfoldersMap[sourceURL] = sorted
        }
        self.cachedSubfolders = subfoldersMap
        
        for subfolders in subfoldersMap.values {
            for subfolder in subfolders {
                subfolderPhotoCounts[subfolder] = photoSetsBySubfolder[subfolder]?.count ?? 0
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
    
} 
