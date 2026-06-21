//
//  PhotomatorSortApp.swift
//  PhotomatorSort
//

import SwiftUI
import AppKit

@main
struct DuckSortApp: App {
    // Observe shared state so menu commands reflect customizable hotkeys and
    // enable/disable as the active library appears.
    @ObservedObject private var windowManager = FloatingWindowManager.shared
    @ObservedObject private var preferences = UserPreferences.shared

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            SidebarCommands()
            TextEditingCommands()

            CommandGroup(after: .sidebar) {
                Toggle("JPEG Only Mode", isOn: Binding(
                    get: { windowManager.activeViewModel?.isJpegOnlyMode ?? false },
                    set: { windowManager.activeViewModel?.isJpegOnlyMode = $0 }
                ))
                .optionalKeyboardShortcut(KeyboardShortcutInfo.parse(preferences.jpegOnlyHotkey).keyboardShortcut)
                .disabled(!windowManager.isReady)
            }

            CommandGroup(after: .newItem) {
                Button("Add Source Folder...") {
                    FloatingWindowManager.shared.activeViewModel?.addSourceDirectory()
                }
                .optionalKeyboardShortcut(KeyboardShortcutInfo.parse(preferences.openSourceHotkey).keyboardShortcut)
                .disabled(!windowManager.isReady)

                Button("Import...") {
                    FloatingWindowManager.shared.activeViewModel?.importItems()
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(!windowManager.isReady)
            }

            CommandMenu("Tools") {
                Button("Tag Manager...") {
                    if let vm = FloatingWindowManager.shared.activeViewModel {
                        FloatingWindowManager.shared.showTagManager(viewModel: vm)
                    }
                }
                .optionalKeyboardShortcut(KeyboardShortcutInfo.parse(preferences.tagManagerHotkey).keyboardShortcut)
                .disabled(!windowManager.isReady)

                Button("Export Routing Rules...") {
                    if let vm = FloatingWindowManager.shared.activeViewModel {
                        FloatingWindowManager.shared.showRuleEditor(viewModel: vm)
                    }
                }
                .optionalKeyboardShortcut(KeyboardShortcutInfo.parse(preferences.ruleEditorHotkey).keyboardShortcut)
                .disabled(!windowManager.isReady)

                Divider()

                Button("Keyboard Shortcuts...") {
                    if let vm = FloatingWindowManager.shared.activeViewModel {
                        FloatingWindowManager.shared.showShortcutsViewer(viewModel: vm)
                    }
                }
                .keyboardShortcut("/", modifiers: .command)
                .disabled(!windowManager.isReady)
            }
        }
    }
}
