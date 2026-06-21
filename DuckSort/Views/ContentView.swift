//
//  ContentView.swift
//  PhotomatorSort
//

import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var viewModel = PhotoLibraryViewModel()

    @State private var showSourcesPopover = false
    @State private var isDropTargeted = false

    var body: some View {
        GeometryReader { _ in
            HStack(spacing: 0) {
                SidebarView(viewModel: viewModel)
                
                VStack(spacing: 0) {
                    customTopBar
                        .zIndex(1)
                    
                    VStack(spacing: 12) {
                        if viewModel.photoSets.isEmpty {
                            EmptyLibraryView(isScanning: viewModel.isScanning) {
                                viewModel.importItems()
                            }
                        } else {
                            PhotoGridView(viewModel: viewModel)
                        }

                        TransferFooter(viewModel: viewModel)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(PhotomatorTheme.background)
                    .dropDestination(for: URL.self) { urls, _ in
                        viewModel.importURLs(urls)
                        return !urls.isEmpty
                    } isTargeted: { targeted in
                        isDropTargeted = targeted
                    }
                    .overlay {
                        if isDropTargeted {
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(PhotomatorTheme.selectedBlue, style: StrokeStyle(lineWidth: 3, dash: [8]))
                                .padding(6)
                                .allowsHitTesting(false)
                                .transition(.opacity)
                        }
                    }
                    .animation(.easeInOut(duration: 0.15), value: isDropTargeted)
                }
            }
        }
        .frame(minWidth: 920, minHeight: 640)
        .navigationTitle("")
        .overlay {
            // Full-canvas large image viewer overlay
            if viewModel.isLargeImageViewerOpen {
                LargeImageViewer(viewModel: viewModel)
                    .transition(.opacity)
            }
        }
        .animation(.smooth, value: viewModel.isLargeImageViewerOpen)
        .alert("DuckSort", isPresented: errorBinding) {
            Button("OK", role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .onAppear {
            FloatingWindowManager.shared.activeViewModel = viewModel
            viewModel.registerKeyboardMonitor { event in
                return handleGlobalKeyPress(event)
            }
        }
        .ignoresSafeArea(.container, edges: .top)
    }

    private var customTopBar: some View {
        HStack(spacing: 12) {
            Text("DuckSort")
                .font(.headline.weight(.semibold))
                .padding(.trailing, 4)

            Button {
                showSourcesPopover = true
            } label: {
                Label(
                    viewModel.sourceDirectories.isEmpty
                        ? "Add Source"
                        : "\(viewModel.sourceDirectories.count) Source\(viewModel.sourceDirectories.count == 1 ? "" : "s")",
                    systemImage: "photo.on.rectangle.angled"
                )
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .liquidGlassButton(isHovered: false)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showSourcesPopover, arrowEdge: .bottom) {
                SourceFoldersPopoverView(viewModel: viewModel)
            }

            Button {
                viewModel.clearSelection()
            } label: {
                Label("Unselect All", systemImage: "checkmark.circle.badge.xmark")
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .liquidGlassButton(isHovered: false)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.selectedCount == 0)

            Spacer()

            Button {
                viewModel.isJpegOnlyMode.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: viewModel.isJpegOnlyMode ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(viewModel.isJpegOnlyMode ? .blue : .secondary)
                    Text("JPEG Only")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .liquidGlassButton(isHovered: false, isApplied: viewModel.isJpegOnlyMode)
            }
            .buttonStyle(.plain)
            .help("Only scan JPEGs and disable edit warnings")

        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .background(
            Rectangle()
                .fill(PhotomatorTheme.toolbarBackground)
                .ignoresSafeArea()
        )
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(PhotomatorTheme.separator),
            alignment: .bottom
        )
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
        
        if String(char) != shortcut.key.lowercased() {
            return false
        }
        
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasShift = flags.contains(.shift)
        let hasControl = flags.contains(.control)
        let hasOption = flags.contains(.option)
        let hasCommand = flags.contains(.command)
        
        return hasShift == shortcut.shift &&
               hasControl == shortcut.control &&
               hasOption == shortcut.option &&
               hasCommand == shortcut.command
    }

    private func handleGlobalKeyPress(_ event: NSEvent) -> Bool {
        // Ignore keys while a floating utility panel (Tag Manager, Routing Rules,
        // Shortcuts) is focused, so culling shortcuts don't mutate the hidden grid.
        if let keyWindow = NSApp.keyWindow, keyWindow.isFloatingPanel {
            return false
        }
        if isFirstResponderTextField(in: NSApp.keyWindow) {
            return false
        }

        // App-action shortcuts (Add Source, Tag Manager, Routing Rules) are owned
        // by the menu commands so a single, user-customizable binding stays in sync.

        // Intercept Command + A (Select All in the current view)
        if let chars = event.charactersIgnoringModifiers?.lowercased(),
           chars == "a",
           event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command {
            viewModel.selectVisiblePhotoSets()
            return true
        }

        if viewModel.isLargeImageViewerOpen {
            return handleViewerKeyPress(event)
        } else {
            return handleGridKeyPress(event)
        }
    }

    private func handleViewerKeyPress(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 53: // Escape
            viewModel.closeLargeImageViewer()
            return true

        case 123, 126: // Left / Up Arrow
            viewModel.navigateFocusedPhoto(delta: -1)
            return true

        case 124, 125: // Right / Down Arrow
            viewModel.navigateFocusedPhoto(delta: 1)
            return true

        case 36, 49: // Return (36) or Space (49)
            viewModel.closeLargeImageViewer()
            return true

        case 48: // Tab
            let direction = event.modifierFlags.contains(.shift) ? -1 : 1
            viewModel.cycleCurrentCategory(direction: direction)
            return true

        default:
            if let chars = event.charactersIgnoringModifiers, chars.count == 1 {
                let char = chars.first!
                let isPlainKey = event.modifierFlags.intersection([.command, .control, .option]).isEmpty

                // 's' or 'S' to toggle selection
                if isPlainKey, char == "s" || char == "S" {
                    if let photo = viewModel.currentFocusedPhotoSet {
                        viewModel.toggleSelection(for: photo.id)
                    }
                    return true
                }

                // 'i' or 'I' to toggle inspector
                if isPlainKey, char == "i" || char == "I" {
                    viewModel.isInspectorOpen.toggle()
                    return true
                }

                // Rating
                if let rating = Int(String(char)), rating >= 0, rating <= 5 {
                    if let photo = viewModel.currentFocusedPhotoSet {
                        if rating == 0 {
                            viewModel.clearTags(for: photo.id)
                            viewModel.setRating(nil, for: photo.id)
                            viewModel.setPick(0, for: photo.id)
                        } else {
                            viewModel.setRating(rating, for: photo.id)
                        }
                    }
                    return true
                }

                // Pick
                if char == "z" || char == "Z" {
                    if let photo = viewModel.currentFocusedPhotoSet { viewModel.setPick(1, for: photo.id) }
                    return true
                }
                if char == "x" || char == "X" {
                    if let photo = viewModel.currentFocusedPhotoSet { viewModel.setPick(-1, for: photo.id) }
                    return true
                }
                if char == "u" || char == "U" {
                    if let photo = viewModel.currentFocusedPhotoSet { viewModel.setPick(0, for: photo.id) }
                    return true
                }

                // Custom hotkeys (with modifier support)
                for tag in viewModel.tagStore.tags {
                    if let shortcut = tag.shortcutInfo, eventMatchesShortcut(event, shortcut: shortcut) {
                        viewModel.applyTagToFocusedPhoto(tag)
                        return true
                    }
                }
            }
            return false
        }
    }

    private func handleGridKeyPress(_ event: NSEvent) -> Bool {
        let count = viewModel.filteredPhotoSets.count
        guard count > 0 else { return false }

        let cols = max(1, viewModel.gridColumnCount)

        switch event.keyCode {
        case 123: // Left Arrow
            viewModel.focusedPhotoIndex = max(0, viewModel.focusedPhotoIndex - 1)
            return true

        case 124: // Right Arrow
            viewModel.focusedPhotoIndex = min(count - 1, viewModel.focusedPhotoIndex + 1)
            return true

        case 126: // Up Arrow
            viewModel.focusedPhotoIndex = max(0, viewModel.focusedPhotoIndex - cols)
            return true

        case 125: // Down Arrow
            viewModel.focusedPhotoIndex = min(count - 1, viewModel.focusedPhotoIndex + cols)
            return true

        case 36, 49: // Return (36) or Space (49)
            viewModel.openLargeImageViewer()
            return true

        default:
            if let chars = event.charactersIgnoringModifiers, chars.count == 1 {
                let char = chars.first!
                let isPlainKey = event.modifierFlags.intersection([.command, .control, .option]).isEmpty

                // 's' or 'S' to toggle selection
                if isPlainKey, char == "s" || char == "S" {
                    if viewModel.focusedPhotoIndex >= 0 && viewModel.focusedPhotoIndex < count {
                        let photo = viewModel.filteredPhotoSets[viewModel.focusedPhotoIndex]
                        viewModel.toggleSelection(for: photo.id)
                    }
                    return true
                }

                // 'i' or 'I' to toggle inspector
                if isPlainKey, char == "i" || char == "I" {
                    viewModel.isInspectorOpen.toggle()
                    return true
                }

                // Rating
                if let rating = Int(String(char)), rating >= 0, rating <= 5 {
                    if viewModel.focusedPhotoIndex >= 0 && viewModel.focusedPhotoIndex < count {
                        let photo = viewModel.filteredPhotoSets[viewModel.focusedPhotoIndex]
                        if rating == 0 {
                            viewModel.clearTags(for: photo.id)
                            viewModel.setRating(nil, for: photo.id)
                            viewModel.setPick(0, for: photo.id)
                        } else {
                            viewModel.setRating(rating, for: photo.id)
                        }
                    }
                    return true
                }

                // Pick
                if char == "z" || char == "Z" {
                    if viewModel.focusedPhotoIndex >= 0 && viewModel.focusedPhotoIndex < count {
                        let photo = viewModel.filteredPhotoSets[viewModel.focusedPhotoIndex]
                        viewModel.setPick(1, for: photo.id)
                    }
                    return true
                }
                if char == "x" || char == "X" {
                    if viewModel.focusedPhotoIndex >= 0 && viewModel.focusedPhotoIndex < count {
                        let photo = viewModel.filteredPhotoSets[viewModel.focusedPhotoIndex]
                        viewModel.setPick(-1, for: photo.id)
                    }
                    return true
                }
                if char == "u" || char == "U" {
                    if viewModel.focusedPhotoIndex >= 0 && viewModel.focusedPhotoIndex < count {
                        let photo = viewModel.filteredPhotoSets[viewModel.focusedPhotoIndex]
                        viewModel.setPick(0, for: photo.id)
                    }
                    return true
                }

                // Custom hotkeys (with modifier support)
                for tag in viewModel.tagStore.tags {
                    if let shortcut = tag.shortcutInfo, eventMatchesShortcut(event, shortcut: shortcut) {
                        if viewModel.focusedPhotoIndex >= 0 && viewModel.focusedPhotoIndex < count {
                            viewModel.applyTagToFocusedPhoto(tag)
                        }
                        return true
                    }
                }
            }
            return false
        }
    }

}

// MARK: - Keyboard Shortcuts Reference & Configuration Popover

struct ShortcutsPopoverView: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel
    var onClose: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Spacer()
                Button("Done", action: onClose)
                    .keyboardShortcut(.defaultAction)
                Button("", action: onClose)
                    .keyboardShortcut(.cancelAction)
                    .hidden()
            }
            .padding(.bottom, 2)

            // Section 1: General App Shortcuts (Editable!)
            VStack(alignment: .leading, spacing: 8) {
                Text("APP ACTIONS")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)

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
            }

            Divider()

            // Section 2: Culling Shortcuts Reference (Static)
            VStack(alignment: .leading, spacing: 6) {
                Text("CULLING CONTROL")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 2)

                shortcutRow(label: "Toggle Selection", shortcut: "S")
                shortcutRow(label: "Clear All Tags", shortcut: "0")
                shortcutRow(label: "Close Large Viewer", shortcut: "Esc")
                shortcutRow(label: "Navigate Photos", shortcut: "← / → / ↑ / ↓")
                shortcutRow(label: "Next/Prev Category", shortcut: "Tab / ⇧Tab")
                shortcutRow(label: "Select Visible (Grid)", shortcut: "⌘A")
        }

            if !viewModel.tagStore.tags.isEmpty {
                Divider()

                // Section 3: Tag Hotkeys Reference
                VStack(alignment: .leading, spacing: 6) {
                    Text("TAG HOTKEYS")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 2)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(viewModel.tagStore.tags) { tag in
                                if let shortcut = tag.shortcutInfo {
                                    HStack {
                                        HStack(spacing: 6) {
                                            Circle()
                                                .fill(tag.color)
                                                .frame(width: 6, height: 6)
                                            Text(tag.name)
                                                .font(.subheadline)
                                        }
                                        Spacer()
                                        Text(shortcut.displayString)
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(minWidth: 320, idealWidth: 360, maxWidth: .infinity, minHeight: 400, idealHeight: 480, maxHeight: .infinity, alignment: .topLeading)
    }

    private func shortcutRow(label: String, shortcut: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
            Spacer()
            Text(shortcut)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}
