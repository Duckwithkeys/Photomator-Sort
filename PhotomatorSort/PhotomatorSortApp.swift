//
//  PhotomatorSortApp.swift
//  PhotomatorSort
//

import SwiftUI
import AppKit

@main
struct PhotomatorSortApp: App {
    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .commands {
            SidebarCommands()
            TextEditingCommands()
            
            CommandMenu("Tools") {
                Button("Tag Manager...") {
                    if let vm = FloatingWindowManager.shared.activeViewModel {
                        FloatingWindowManager.shared.showTagManager(viewModel: vm)
                    }
                }
                .keyboardShortcut("t", modifiers: .command)
                
                Button("Export Routing Rules...") {
                    if let vm = FloatingWindowManager.shared.activeViewModel {
                        FloatingWindowManager.shared.showRuleEditor(viewModel: vm)
                    }
                }
                .keyboardShortcut("r", modifiers: .command)
                
                Divider()
                
                Button("Keyboard Shortcuts...") {
                    if let vm = FloatingWindowManager.shared.activeViewModel {
                        FloatingWindowManager.shared.showShortcutsViewer(viewModel: vm)
                    }
                }
                .keyboardShortcut("/", modifiers: .command)
            }
        }
    }
}
