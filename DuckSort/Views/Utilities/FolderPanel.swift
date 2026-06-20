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

    /// Choose any combination of files and folders to import.
    static func chooseItems(title: String) -> [URL] {
        let panel = NSOpenPanel()
        panel.title = title
        panel.message = "Choose photos or folders to import"
        panel.prompt = "Import"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false

        return panel.runModal() == .OK ? panel.urls : []
    }
}
