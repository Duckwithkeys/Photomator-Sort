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

                Toggle("Show Advanced EXIF", isOn: Binding(
                    get: { preferences.showAdvancedEXIF },
                    set: { newValue in
                        preferences.showAdvancedEXIF = newValue
                        preferences.save()
                    }
                ))
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(!windowManager.isReady)

                Divider()

                Button("XMP Tags Not in Active Pack…") {
                    if let vm = windowManager.activeViewModel {
                        FloatingWindowManager.shared.showXMPTagInspector(viewModel: vm)
                    }
                }
                .keyboardShortcut("x", modifiers: [.command, .shift])
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

            // Tag pack quick-switcher. ⌘1–⌘9 jump between packs, mirroring
            // the order shown in Settings → Tags and Help → Show Welcome Guide.
            // Built-in packs first, then user-created packs by name.
            CommandMenu("Tag Packs") {
                let packs = FloatingWindowManager.shared.activeViewModel?.packLibrary.packs ?? []
                let firstNine = Array(packs.prefix(9))
                ForEach(Array(firstNine.enumerated()), id: \.element.id) { index, pack in
                    Button("Switch to \(pack.name)") {
                        FloatingWindowManager.shared.activeViewModel?.switchTagPack(id: pack.id)
                    }
                    .keyboardShortcut(
                        KeyEquivalent(Character(String(index + 1))),
                        modifiers: [.command]
                    )
                    .disabled(!windowManager.isReady)
                }
                if firstNine.isEmpty {
                    Text("No packs yet")
                }
                Divider()
                Button("Show Welcome Guide…") {
                    NotificationCenter.default.post(
                        name: .ducksortShowOnboarding,
                        object: nil
                    )
                }
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

            // Custom Help menu so users can re-run the onboarding wizard
            // from the menu bar after the first launch.
            CommandGroup(replacing: .help) {
                Button("Show Welcome Guide…") {
                    NotificationCenter.default.post(
                        name: .ducksortShowOnboarding,
                        object: nil
                    )
                }
                .keyboardShortcut("/", modifiers: .command)
            }
        }
    }
}

extension Notification.Name {
    static let ducksortShowOnboarding = Notification.Name("ducksortShowOnboarding")
}
