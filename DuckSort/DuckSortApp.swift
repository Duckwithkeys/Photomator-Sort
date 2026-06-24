//
//  PhotomatorSortApp.swift
//  PhotomatorSort
//

import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

@main
struct DuckSortApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
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

            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    if let vm = FloatingWindowManager.shared.activeViewModel {
                        FloatingWindowManager.shared.showSettings(viewModel: vm)
                    }
                }
                .keyboardShortcut(",", modifiers: .command)
                .disabled(!windowManager.isReady)
            }
        }
    }
}
