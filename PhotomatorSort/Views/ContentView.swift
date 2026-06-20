//
//  ContentView.swift
//  PhotomatorSort
//

import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var viewModel = PhotoLibraryViewModel()
    @State private var windowWidth: CGFloat = 920

    @State private var showSourcesPopover = false

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 12) {
                if viewModel.photoSets.isEmpty {
                    EmptyLibraryView(isScanning: viewModel.isScanning) {
                        viewModel.addSourceDirectory()
                    }
                } else {
                    PhotoGridView(viewModel: viewModel)
                }
                
                TransferFooter(viewModel: viewModel)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                LinearGradient(
                    colors: [Color(NSColor.windowBackgroundColor), Color(NSColor.underPageBackgroundColor).opacity(0.85)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .onAppear {
                windowWidth = geometry.size.width
            }
            .onChange(of: geometry.size.width) { _, newWidth in
                windowWidth = newWidth
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
        .alert("Photomator Sort", isPresented: errorBinding) {
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
        .toolbar {
            ToolbarItem(id: "title", placement: .navigation) {
                Text("Photomator Sort")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .padding(.trailing, 6)
            }

            ToolbarItem(id: "sources", placement: .navigation) {
                Button {
                    showSourcesPopover = true
                } label: {
                    Label(
                        viewModel.sourceDirectories.isEmpty
                            ? "Add Source"
                            : "\(viewModel.sourceDirectories.count) Source\(viewModel.sourceDirectories.count == 1 ? "" : "s")",
                        systemImage: "photo.on.rectangle.angled"
                    )
                }
                .help("Manage source folders")
                .popover(isPresented: $showSourcesPopover, arrowEdge: .bottom) {
                    SourceFoldersPopoverView(viewModel: viewModel)
                }
            }

            ToolbarItem(id: "deselectAll", placement: .navigation) {
                Button {
                    viewModel.clearSelection()
                } label: {
                    Label("Unselect All", systemImage: "checkmark.circle.badge.xmark")
                }
                .disabled(viewModel.selectedCount == 0)
                .help("Unselect all photo sets")
            }

            ToolbarItem(id: "jpegOnly", placement: .navigation) {
                Toggle("JPEG Only", isOn: $viewModel.isJpegOnlyMode)
                    .toggleStyle(.switch)
                    .help("Only scan JPEGs and disable edit warnings")
            }

            ToolbarItem(id: "filterRule", placement: .navigation) {
                Picker("Filter", selection: $viewModel.filterRule) {
                    ForEach(PhotoFilterRule.allCases) { rule in
                        Text(rule.rawValue)
                            .tag(rule)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 360)
            }
        }
        .toolbar(viewModel.isLargeImageViewerOpen ? .hidden : .visible, for: .windowToolbar)
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
        if isFirstResponderTextField(in: NSApp.keyWindow) {
            return false
        }

        // Intercept general app shortcuts
        if let tagManagerShortcut = viewModel.tagManagerShortcutInfo,
           eventMatchesShortcut(event, shortcut: tagManagerShortcut) {
            FloatingWindowManager.shared.showTagManager(viewModel: viewModel)
            return true
        }
        if let ruleEditorShortcut = viewModel.ruleEditorShortcutInfo,
           eventMatchesShortcut(event, shortcut: ruleEditorShortcut) {
            FloatingWindowManager.shared.showRuleEditor(viewModel: viewModel)
            return true
        }
        if let openSourceShortcut = viewModel.openSourceShortcutInfo,
           eventMatchesShortcut(event, shortcut: openSourceShortcut) {
            viewModel.addSourceDirectory()
            return true
        }

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

                // 's' or 'S' to toggle selection
                if char == "s" || char == "S" {
                    if let photo = viewModel.currentFocusedPhotoSet {
                        viewModel.toggleSelection(for: photo.id)
                    }
                    return true
                }

                // 'i' or 'I' to toggle inspector
                if char == "i" || char == "I" {
                    viewModel.isInspectorOpen.toggle()
                    return true
                }


                if char == "0" {
                    if let photo = viewModel.currentFocusedPhotoSet {
                        viewModel.clearTags(for: photo.id)
                    }
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

        let cols = columnsCount(for: windowWidth)

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

                // 's' or 'S' to toggle selection
                if char == "s" || char == "S" {
                    if viewModel.focusedPhotoIndex >= 0 && viewModel.focusedPhotoIndex < count {
                        let photo = viewModel.filteredPhotoSets[viewModel.focusedPhotoIndex]
                        viewModel.toggleSelection(for: photo.id)
                    }
                    return true
                }

                // 'i' or 'I' to toggle inspector
                if char == "i" || char == "I" {
                    viewModel.isInspectorOpen.toggle()
                    return true
                }


                if char == "0" {
                    if viewModel.focusedPhotoIndex >= 0 && viewModel.focusedPhotoIndex < count {
                        let photo = viewModel.filteredPhotoSets[viewModel.focusedPhotoIndex]
                        viewModel.clearTags(for: photo.id)
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

    private func columnsCount(for width: CGFloat) -> Int {
        let minWidth: CGFloat = 208
        let spacing: CGFloat = 18
        let padding: CGFloat = 56 // 28 * 2
        let availableWidth = width - padding
        let count = Int(floor((availableWidth + spacing) / (minWidth + spacing)))
        return max(1, count)
    }

}

// MARK: - Keyboard Shortcuts Reference & Configuration Popover

struct ShortcutsPopoverView: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Keyboard Shortcuts")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Done") {
                    NSApp.keyWindow?.close()
                }
                .keyboardShortcut(.defaultAction)
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
                    .frame(maxHeight: 120)
                }
            }
        }
        .padding(14)
        .frame(width: 320)
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
