//
//  FolderPanel.swift
//  PhotomatorSort
//

import AppKit

@MainActor
enum FolderPanel {
    static func chooseDirectory(title: String) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        return panel.runModal() == .OK ? panel.url : nil
    }
}
