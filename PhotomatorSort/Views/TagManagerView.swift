//
//  TagManagerView.swift
//  PhotomatorSort
//
//  Sheet for creating, renaming, and deleting tag categories and tags.
//  Tags are grouped by category, and each tag has an optional hotkey
//  used in the culling viewer.
//

import SwiftUI
import UniformTypeIdentifiers

struct TagManagerView: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel
    @ObservedObject var tagStore: TagStore
    @Environment(\.dismiss) private var dismiss
    
    @State private var newCategoryName: String = ""
    @State private var newTagText: String = ""
    @State private var newTagCategoryID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Tag Manager")
                    .font(.title2.weight(.semibold))
                
                Button(action: importContacts) {
                    Label("Import Contacts...", systemImage: "person.crop.circle.badge.plus")
                }
                .buttonStyle(.bordered)
                
                Spacer()
                Button("Done") {
                    dismiss()
                    NSApp.keyWindow?.close()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(tagStore.categories) { category in
                        categorySection(category)
                    }

                    addCategoryRow
                }
                .padding(20)
            }
        }
        .frame(minWidth: 640, minHeight: 520)
        .onAppear {
            if newTagCategoryID == nil {
                newTagCategoryID = tagStore.categories.first?.id
            }
        }
    }

    @ViewBuilder
    private func categorySection(_ category: TagCategory) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Category name", text: Binding(
                    get: { category.name },
                    set: { tagStore.renameCategory(id: category.id, to: $0) }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 260)

                Spacer()

                Button(role: .destructive) {
                    tagStore.deleteCategory(id: category.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete category and all its tags")
            }

            let tagsInCategory = tagStore.tags(in: category.id)
            if tagsInCategory.isEmpty {
                Text("No tags yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(tagsInCategory) { tag in
                    tagRow(tag)
                }
            }

            addTagRow(for: category)
            Divider()
        }
    }

    @ViewBuilder
    private func tagRow(_ tag: CustomTag) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(tag.color)
                .frame(width: 12, height: 12)

            TextField("Tag name", text: Binding(
                get: { tag.name },
                set: { newName in
                    var updated = tag
                    updated.name = newName
                    tagStore.updateTag(updated)
                }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 220)

            HStack(spacing: 4) {
                Text("Hotkey")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ShortcutRecorderView(hotkey: Binding(
                    get: { tag.hotkey },
                    set: { newValue in
                        var updated = tag
                        updated.hotkey = newValue
                        tagStore.updateTag(updated)
                    }
                ))
            }

            ColorPicker("", selection: Binding(
                get: { tag.color },
                set: { newColor in
                    var updated = tag
                    updated.colorHex = newColor.toHex() ?? tag.colorHex
                    tagStore.updateTag(updated)
                }
            ), supportsOpacity: false)
            .labelsHidden()
            .frame(width: 36)

            Button(role: .destructive) {
                tagStore.deleteTag(id: tag.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .padding(4)
            }
            .buttonStyle(.plain)
            .help("Delete tag")
        }
    }

    @ViewBuilder
    private func addTagRow(for category: TagCategory) -> some View {
        HStack(spacing: 8) {
            TextField("New tag name", text: Binding(
                get: { newTagCategoryID == category.id ? newTagText : "" },
                set: { newValue in
                    newTagCategoryID = category.id
                    newTagText = newValue
                }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 220)
            .onSubmit { commitNewTag(for: category) }

            Button("Add Tag") {
                commitNewTag(for: category)
            }
            .disabled(newTagText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func commitNewTag(for category: TagCategory) {
        let raw = newTagText.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return }
        tagStore.addTag(name: raw, categoryID: category.id)
        newTagText = ""
        newTagCategoryID = category.id
    }

    private var addCategoryRow: some View {
        HStack(spacing: 8) {
            TextField("New category name", text: $newCategoryName)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 260)
                .onSubmit(commitNewCategory)

            Button("Add Category") {
                commitNewCategory()
            }
            .disabled(newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func commitNewCategory() {
        let trimmed = newCategoryName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        tagStore.addCategory(name: trimmed)
        newCategoryName = ""
    }

    private func importContacts() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.vCard]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "Import Contacts as Tags"
        panel.prompt = "Import"
        
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                let names = parseVCardNames(content)
                guard !names.isEmpty else { return }
                
                let categoryName = "People"
                let category: TagCategory
                if let existing = tagStore.categories.first(where: { $0.name.lowercased() == categoryName.lowercased() }) {
                    category = existing
                } else {
                    category = tagStore.addCategory(name: categoryName)
                }
                
                for name in names {
                    let existingTags = tagStore.tags(in: category.id)
                    if !existingTags.contains(where: { $0.name.lowercased() == name.lowercased() }) {
                        _ = tagStore.addTag(name: name, categoryID: category.id)
                    }
                }
                
                if newTagCategoryID == nil {
                    newTagCategoryID = category.id
                }
            } catch {
                print("Failed to import contacts: \(error)")
            }
        }
    }
    
    private func parseVCardNames(_ content: String) -> [String] {
        var names: [String] = []
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.uppercased().hasPrefix("FN:") {
                let name = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty {
                    names.append(name)
                }
            } else if trimmed.uppercased().hasPrefix("FN;") {
                let parts = trimmed.split(separator: ":", maxSplits: 1)
                if parts.count == 2 {
                    let name = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty {
                        names.append(name)
                    }
                }
            }
        }
        return Array(Set(names)).sorted()
    }
}

// MARK: - Color hex helper

extension Color {
    func toHex() -> String? {
        let nsColor = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)
        let r = Int(round(nsColor.redComponent * 255))
        let g = Int(round(nsColor.greenComponent * 255))
        let b = Int(round(nsColor.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
