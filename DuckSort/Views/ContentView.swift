//
//  ContentView.swift
//  DuckSort
//

import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var viewModel = PhotoLibraryViewModel()
    @State private var showOnboarding: Bool = false

    var body: some View {
        MainLayout(viewModel: viewModel)
            .frame(minWidth: 920, minHeight: 640)
            .navigationTitle("DuckSort")
            .toolbar { mainToolbar }
            .overlay {
                if viewModel.isLargeImageViewerOpen {
                    LargeImageViewer(viewModel: viewModel)
                        .transition(.opacity)
                }
            }
            .overlay {
                if showOnboarding {
                    OnboardingFlow(viewModel: viewModel) {
                        showOnboarding = false
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    .zIndex(100)
                }
            }
            .animation(.easeInOut(duration: 0.22), value: showOnboarding)
            .animation(.smooth, value: viewModel.isLargeImageViewerOpen)
            .alert("DuckSort", isPresented: errorBinding) {
                Button("OK", role: .cancel) { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .onAppear {
                FloatingWindowManager.shared.activeViewModel = viewModel
                viewModel.registerKeyboardMonitor { event in
                    handleGlobalKeyPress(event)
                }
                // Show the first-launch wizard unless the user has already
                // completed it (or dismissed it) in a previous session.
                if !UserPreferences.shared.hasCompletedOnboarding {
                    showOnboarding = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .ducksortShowOnboarding)) { _ in
                showOnboarding = true
            }
    }

    @ToolbarContentBuilder
    private var mainToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                viewModel.isSidebarHidden.toggle()
            } label: {
                Label("Toggle Sidebar", systemImage: "sidebar.leading")
            }
            .help("Show or hide the sidebar")
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                viewModel.addSourceDirectory()
            } label: {
                Label("Add Source", systemImage: "plus.rectangle.on.folder")
            }
            .help("Add a source folder (⇧⌘O)")
        }

        ToolbarItem(placement: .primaryAction) {
            Toggle(isOn: Binding(
                get: { viewModel.isJpegOnlyMode },
                set: { viewModel.isJpegOnlyMode = $0 }
            )) {
                Label("JPEG Only", systemImage: "photo")
            }
            .help("Show only JPEG derivatives")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )
    }

    private func isFirstResponderTextField(in window: NSWindow?) -> Bool {
        guard let firstResponder = window?.firstResponder else { return false }
        if let textView = firstResponder as? NSTextView {
            return textView.isEditable
        }
        if let textField = firstResponder as? NSTextField {
            return textField.isEditable
        }
        return false
    }

    // MARK: - Global Key Handling

    private func eventMatchesShortcut(_ event: NSEvent, shortcut: KeyboardShortcutInfo) -> Bool {
        guard let chars = event.charactersIgnoringModifiers?.lowercased(),
              chars.count == 1,
              let char = chars.first else { return false }

        if String(char) != shortcut.key.lowercased() { return false }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return flags.contains(.shift)    == shortcut.shift &&
               flags.contains(.control)  == shortcut.control &&
               flags.contains(.option)   == shortcut.option &&
               flags.contains(.command)  == shortcut.command
    }

    private func handleGlobalKeyPress(_ event: NSEvent) -> Bool {
        if let keyWindow = NSApp.keyWindow, keyWindow.isFloatingPanel {
            return false
        }
        if isFirstResponderTextField(in: NSApp.keyWindow) {
            return false
        }

        if let chars = event.charactersIgnoringModifiers?.lowercased(),
           chars == "a",
           event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command {
            viewModel.selectVisiblePhotoSets()
            return true
        }

        return viewModel.isLargeImageViewerOpen
            ? handleViewerKeyPress(event)
            : handleGridKeyPress(event)
    }

    private func handleViewerKeyPress(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 53: // Esc
            viewModel.closeLargeImageViewer()
            return true

        case 123, 126:
            viewModel.navigateFocusedPhoto(delta: -1)
            return true

        case 124, 125:
            viewModel.navigateFocusedPhoto(delta: 1)
            return true

        case 36, 49: // Return / Space
            viewModel.closeLargeImageViewer()
            return true

        case 33, 30: // [ / ]
            let direction = event.keyCode == 33 ? 1 : -1
            viewModel.cycleCurrentCategory(direction: direction)
            return true

        default:
            guard let chars = event.charactersIgnoringModifiers, chars.count == 1 else {
                return false
            }
            return handlePlainViewerKey(char: chars.first!, event: event)
        }
    }

    private func handlePlainViewerKey(char: Character, event: NSEvent) -> Bool {
        let isPlainKey = event.modifierFlags.intersection([.command, .control, .option]).isEmpty

        if isPlainKey, char == "s" || char == "S" {
            if let photo = viewModel.currentFocusedPhotoSet {
                viewModel.toggleSelection(for: photo.id)
            }
            return true
        }

        if isPlainKey, char == "i" || char == "I" {
            viewModel.isInspectorOpen.toggle()
            return true
        }

        if let rating = Int(String(char)), (0...5).contains(rating) {
            let ids = viewModel.batchTargetPhotoSets.map(\.id)
            if !ids.isEmpty {
                if rating == 0 {
                    viewModel.clearTags(forIDs: ids)
                    viewModel.setRating(nil, forIDs: ids)
                    viewModel.setPick(0, forIDs: ids)
                } else {
                    viewModel.setRating(rating, forIDs: ids)
                }
            }
            return true
        }

        switch char.lowercased() {
        case "z":
            // Pick-flag is a culling workflow; stays single-photo.
            if let photo = viewModel.currentFocusedPhotoSet { viewModel.setPick(1, for: photo.id) }
            return true
        case "x":
            if let photo = viewModel.currentFocusedPhotoSet { viewModel.rejectAndAdvance(for: photo.id) }
            return true
        case "u":
            viewModel.clearPickFlagOnSelection()
            return true
        default:
            break
        }

        for tag in viewModel.tagStore.tags {
            if let shortcut = tag.shortcutInfo, eventMatchesShortcut(event, shortcut: shortcut) {
                viewModel.applyTagToSelection(tag)
                return true
            }
        }
        return false
    }

    private func handleGridKeyPress(_ event: NSEvent) -> Bool {
        let count = viewModel.filteredPhotoSets.count
        guard count > 0 else { return false }

        let cols = max(1, viewModel.gridColumnCount)

        switch event.keyCode {
        case 123: // Left
            viewModel.focusedPhotoIndex = max(0, viewModel.focusedPhotoIndex - 1)
            return true
        case 124: // Right
            viewModel.focusedPhotoIndex = min(count - 1, viewModel.focusedPhotoIndex + 1)
            return true
        case 126: // Up
            viewModel.focusedPhotoIndex = max(0, viewModel.focusedPhotoIndex - cols)
            return true
        case 125: // Down
            viewModel.focusedPhotoIndex = min(count - 1, viewModel.focusedPhotoIndex + cols)
            return true

        case 53: // Esc
            if viewModel.selectedCount > 0 {
                viewModel.clearSelection()
                return true
            }
            return false

        case 51, 117: // Backspace / Forward Delete
            if viewModel.selectedCount > 0 {
                viewModel.clearSelection()
                return true
            }
            return false

        case 36, 49: // Return / Space
            viewModel.openLargeImageViewer()
            return true

        default:
            guard let chars = event.charactersIgnoringModifiers, chars.count == 1 else {
                return false
            }
            return handlePlainGridKey(char: chars.first!, event: event)
        }
    }

    private func handlePlainGridKey(char: Character, event: NSEvent) -> Bool {
        let count = viewModel.filteredPhotoSets.count
        let isPlainKey = event.modifierFlags.intersection([.command, .control, .option]).isEmpty

        if isPlainKey, char == "s" || char == "S" {
            if viewModel.focusedPhotoIndex >= 0 && viewModel.focusedPhotoIndex < count {
                let photo = viewModel.filteredPhotoSets[viewModel.focusedPhotoIndex]
                viewModel.toggleSelection(for: photo.id)
            }
            return true
        }

        if isPlainKey, char == "i" || char == "I" {
            // Open the large image viewer for the focused photo. Matches the
            // double-click / Return / Space behavior so the user has one
            // muscle-memory key for "inspect the photo at full size".
            viewModel.openLargeImageViewer()
            return true
        }

        if let rating = Int(String(char)), (0...5).contains(rating) {
            let targets = viewModel.batchTargetPhotoSets
            guard !targets.isEmpty else { return true }
            let ids = targets.map(\.id)
            if rating == 0 {
                viewModel.clearTags(forIDs: ids)
                viewModel.setRating(nil, forIDs: ids)
                viewModel.setPick(0, forIDs: ids)
            } else {
                viewModel.setRating(rating, forIDs: ids)
            }
            return true
        }

        switch char.lowercased() {
        case "z":
            // Pick-flag is culling workflow: always on focused photo only,
            // even if a multi-selection exists. Rejecting N photos at once
            // would surprise users mid-cull.
            if viewModel.focusedPhotoIndex >= 0 && viewModel.focusedPhotoIndex < count {
                viewModel.setPick(1, for: viewModel.filteredPhotoSets[viewModel.focusedPhotoIndex].id)
            }
            return true
        case "x":
            if viewModel.focusedPhotoIndex >= 0 && viewModel.focusedPhotoIndex < count {
                viewModel.rejectAndAdvance(for: viewModel.filteredPhotoSets[viewModel.focusedPhotoIndex].id)
            }
            return true
        case "u":
            viewModel.clearPickFlagOnSelection()
            return true
        default:
            break
        }

        for tag in viewModel.tagStore.tags {
            if let shortcut = tag.shortcutInfo, eventMatchesShortcut(event, shortcut: shortcut) {
                viewModel.applyTagToSelection(tag)
                return true
            }
        }
        return false
    }
}

// MARK: - Keyboard Shortcuts Reference & Configuration Popover

struct ShortcutsPopoverView: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel
    var onClose: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Theme.Space.s14) {
                VStack(alignment: .leading, spacing: Theme.Space.s8) {
                    sectionHeader("APP ACTIONS")

                    HStack {
                        Text("Add Source Folder")
                        Spacer()
                        ShortcutRecorderView(hotkey: $viewModel.openSourceHotkey)
                    }
                    HStack {
                        Text("Open Tag Manager")
                        Spacer()
                        ShortcutRecorderView(hotkey: $viewModel.tagManagerHotkey)
                    }
                    HStack {
                        Text("Open Routing Rules")
                        Spacer()
                        ShortcutRecorderView(hotkey: $viewModel.ruleEditorHotkey)
                    }
                    HStack {
                        Text("Toggle JPEG Only Mode")
                        Spacer()
                        ShortcutRecorderView(hotkey: $viewModel.jpegOnlyHotkey)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: Theme.Space.s6) {
                    sectionHeader("CULLING CONTROL")

                    shortcutRow(label: "Toggle Selection", shortcut: "S")
                    shortcutRow(label: "Clear All Tags", shortcut: "0")
                    shortcutRow(label: "Close Large Viewer", shortcut: "Esc")
                    shortcutRow(label: "Navigate Photos", shortcut: "← / → / ↑ / ↓")
                    shortcutRow(label: "Next/Prev Category", shortcut: "[ / ]")
                    shortcutRow(label: "Select Visible (Grid)", shortcut: "⌘A")
                }

                if !viewModel.tagStore.tags.isEmpty {
                    Divider()

                    VStack(alignment: .leading, spacing: Theme.Space.s6) {
                        sectionHeader("TAG HOTKEYS")

                        ScrollView {
                            VStack(alignment: .leading, spacing: Theme.Space.s6) {
                                ForEach(viewModel.tagStore.tags) { tag in
                                    if let shortcut = tag.shortcutInfo {
                                        HStack {
                                            HStack(spacing: Theme.Space.s6) {
                                                Circle()
                                                    .fill(tag.color)
                                                    .frame(width: 6, height: 6)
                                                Text(tag.name)
                                                    .font(Theme.Font.subheadline)
                                            }
                                            Spacer()
                                            Text(shortcut.displayString)
                                                .font(Theme.Font.monoBody)
                                                .foregroundStyle(Theme.Color.textSecondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(Theme.Space.s20)

            Divider()
            HStack {
                Spacer()
                Button("Done", action: onClose)
                    .keyboardShortcut(.defaultAction)
                Button("", action: onClose)
                    .keyboardShortcut(.cancelAction)
                    .hidden()
            }
            .padding(Theme.Space.s12)
        }
        .frame(width: 340)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(Theme.Font.subheadline)
            .foregroundStyle(Theme.Color.textSecondary)
    }

    private func shortcutRow(label: String, shortcut: String) -> some View {
        HStack {
            Text(label)
                .font(Theme.Font.subheadline)
            Spacer()
            Text(shortcut)
                .font(Theme.Font.monoBody)
                .foregroundStyle(Theme.Color.textSecondary)
        }
    }
}

// MARK: - Main Layout

struct MainLayout: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel
    @State private var isDropTargeted = false

    var body: some View {
        HStack(spacing: 0) {
            if !viewModel.isSidebarHidden {
                SidebarView(viewModel: viewModel)
            }

            VStack(spacing: 0) {
                mainCenter
                TransferFooter(viewModel: viewModel)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.Color.background)
            .dropDestination(for: URL.self) { urls, _ in
                viewModel.importURLs(urls)
                return !urls.isEmpty
            } isTargeted: { targeted in
                isDropTargeted = targeted
            }
            .overlay {
                if isDropTargeted {
                    PulsingDropTargetOverlay()
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: isDropTargeted)
        }
    }

    @ViewBuilder
    private var mainCenter: some View {
        switch (viewModel.photoSets.isEmpty, viewModel.isScanning) {
        case (true, false):
            EmptyLibraryView(isScanning: false) {
                viewModel.importItems()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case (true, true):
            EmptyLibraryView(isScanning: true) {
                viewModel.importItems()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case (false, _):
            PhotoGridView(viewModel: viewModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Pulsing Drop Target Overlay

struct PulsingDropTargetOverlay: View {
    @State private var pulseScale = 1.0
    @State private var phase = 0.0

    var body: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.l)
            .strokeBorder(
                LinearGradient(
                    colors: [Theme.Color.accent, Theme.Color.success, Theme.Color.accent],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                style: StrokeStyle(lineWidth: 3.5, dash: [10, 5], dashPhase: phase)
            )
            .scaleEffect(pulseScale)
            .padding(Theme.Space.s8)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 30.0
                }
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    pulseScale = 0.98
                }
            }
    }
}