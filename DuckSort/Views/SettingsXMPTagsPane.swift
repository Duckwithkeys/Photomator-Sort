//
//  SettingsXMPTagsPane.swift
//  DuckSort
//
//  Shows tag names that were found in on-disk XMP sidecars but are not
//  present in the currently active tag pack. The user can select any
//  subset and import them into an existing category or a new one.
//

import SwiftUI

struct SettingsXMPTagsPane: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel
    @ObservedObject var tagStore: TagStore

    // Selection state
    @State private var selected: Set<String> = []
    // Target category picker
    @State private var targetCategoryID: UUID? = nil
    // New category name sheet
    @State private var showNewCategorySheet = false
    @State private var newCategoryName = ""
    // Import result banner
    @State private var importedCount: Int? = nil
    @State private var showImportedBanner = false

    private var orphaned: [String] {
        viewModel.orphanedXmpTagNames.sorted()
    }

    private var allSelected: Bool {
        !orphaned.isEmpty && selected.count == orphaned.count
    }

    var body: some View {
        SettingsSplitLayout {
            // Left sidebar: target category picker
            sidebar
        } detail: {
            // Right panel: orphaned tag list + actions
            if orphaned.isEmpty {
                emptyState
            } else {
                tagListPanel
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("IMPORT INTO")
                .font(Theme.Font.caption2)
                .tracking(0.3)
                .foregroundStyle(Theme.Color.textSecondary)
                .padding(.horizontal, Theme.Space.s12)
                .padding(.top, Theme.Space.s16)
                .padding(.bottom, Theme.Space.s8)

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(tagStore.categories) { cat in
                        categoryRow(cat)
                    }
                }
                .padding(.horizontal, Theme.Space.s8)
                .padding(.bottom, Theme.Space.s8)
            }

            Divider().padding(.horizontal, Theme.Space.s8)

            Button {
                newCategoryName = ""
                showNewCategorySheet = true
            } label: {
                Label("New Category…", systemImage: "plus")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.accent)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Theme.Space.s12)
            .padding(.vertical, Theme.Space.s10)
        }
        .sheet(isPresented: $showNewCategorySheet) {
            newCategorySheet
        }
    }

    private func categoryRow(_ cat: TagCategory) -> some View {
        let isSelected = targetCategoryID == cat.id
        return HStack(spacing: Theme.Space.s6) {
            Image(systemName: "folder")
                .font(.system(size: 12))
                .foregroundStyle(isSelected ? Theme.Color.accent : Theme.Color.textSecondary)
            Text(cat.name)
                .font(Theme.Font.body)
                .foregroundStyle(isSelected ? Theme.Color.textPrimary : Theme.Color.textSecondary)
                .lineLimit(1)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.Color.accent)
            }
        }
        .padding(.horizontal, Theme.Space.s8)
        .padding(.vertical, Theme.Space.s6)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.m)
                .fill(isSelected ? Theme.Color.rowSelectedFill : Color.clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.m))
        .onTapGesture { targetCategoryID = cat.id }
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    private var newCategorySheet: some View {
        VStack(spacing: Theme.Space.s16) {
            Text("New Category")
                .font(Theme.Font.headline)
                .foregroundStyle(Theme.Color.textPrimary)

            TextField("Category name", text: $newCategoryName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)

            HStack(spacing: Theme.Space.s8) {
                Button("Cancel") {
                    showNewCategorySheet = false
                }
                .buttonStyle(.bordered)

                Button("Create") {
                    let name = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }
                    let cat = tagStore.addCategory(name: name)
                    targetCategoryID = cat.id
                    showNewCategorySheet = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.return)
            }
        }
        .padding(Theme.Space.s24)
        .background(Theme.Color.surfaceBase)
    }

    // MARK: - Tag List Panel

    private var tagListPanel: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack(spacing: Theme.Space.s8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("XMP Tags Not In Active Pack")
                        .font(Theme.Font.bodyBold)
                        .foregroundStyle(Theme.Color.textPrimary)
                    Text("\(orphaned.count) tag\(orphaned.count == 1 ? "" : "s") found in sidecar files")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Color.textSecondary)
                }
                Spacer()

                // Select all toggle
                Button {
                    if allSelected {
                        selected.removeAll()
                    } else {
                        selected = Set(orphaned)
                    }
                } label: {
                    Text(allSelected ? "Deselect All" : "Select All")
                        .font(Theme.Font.caption)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Theme.Color.accent)

                // Import button
                importButton
            }
            .padding(.horizontal, Theme.Space.s16)
            .padding(.vertical, Theme.Space.s12)
            .background(Theme.Color.surfaceBase)

            if showImportedBanner, let count = importedCount {
                importedBanner(count: count)
            }

            Divider()

            // Tag rows
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(orphaned, id: \.self) { tagName in
                        tagRow(tagName)
                        Divider().padding(.leading, 44)
                    }
                }
                .padding(.vertical, Theme.Space.s4)
            }
        }
    }

    private var importButton: some View {
        Button {
            importSelected()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.down.circle.fill")
                Text("Import \(selected.isEmpty ? "" : "\(selected.count) ")Selected")
            }
            .font(Theme.Font.caption)
        }
        .buttonStyle(.borderedProminent)
        .disabled(selected.isEmpty || targetCategoryID == nil)
        .help(targetCategoryID == nil ? "Pick a category in the sidebar first" : "Import selected tags into the active pack")
    }

    private func tagRow(_ tagName: String) -> some View {
        let isChecked = selected.contains(tagName)
        return HStack(spacing: Theme.Space.s12) {
            // Checkbox
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(isChecked ? Theme.Color.accent : Color.clear)
                    .frame(width: 16, height: 16)
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(isChecked ? Theme.Color.accent : Theme.Color.separator, lineWidth: 1.5)
                    .frame(width: 16, height: 16)
                if isChecked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .animation(.easeInOut(duration: 0.12), value: isChecked)

            // Tag chip
            HStack(spacing: Theme.Space.s6) {
                Image(systemName: "tag")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Color.textSecondary)
                Text(tagName)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Color.textPrimary)
            }

            Spacer()

            // "Not in pack" badge
            Text("NOT IN PACK")
                .font(Theme.Font.badgeTiny)
                .tracking(0.4)
                .foregroundStyle(Theme.Color.warning)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule().fill(Theme.Color.warning.opacity(0.14))
                )
        }
        .padding(.horizontal, Theme.Space.s16)
        .padding(.vertical, Theme.Space.s10)
        .background(
            isChecked ? Theme.Color.rowSelectedFill : Color.clear
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if selected.contains(tagName) {
                selected.remove(tagName)
            } else {
                selected.insert(tagName)
            }
        }
        .animation(.easeInOut(duration: 0.1), value: isChecked)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Theme.Space.s16) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 48, weight: .thin))
                .foregroundStyle(Theme.Color.success)

            Text("All XMP Tags Are In Your Active Pack")
                .font(Theme.Font.headline)
                .foregroundStyle(Theme.Color.textPrimary)

            Text("When you load a folder, any sidecar tag names\nnot found in the active pack appear here for import.")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Imported Banner

    private func importedBanner(count: Int) -> some View {
        HStack(spacing: Theme.Space.s8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.Color.success)
            Text("Imported \(count) tag\(count == 1 ? "" : "s") into active pack.")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Color.textPrimary)
            Spacer()
            Button("Dismiss") {
                withAnimation { showImportedBanner = false }
            }
            .font(Theme.Font.caption)
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, Theme.Space.s16)
        .padding(.vertical, Theme.Space.s10)
        .background(Theme.Color.success.opacity(0.12))
    }

    // MARK: - Import Action

    private func importSelected() {
        guard let catID = targetCategoryID, !selected.isEmpty else { return }

        let existingNames = Set(tagStore.tags(in: catID).map { $0.name.lowercased() })
        var importedCount = 0

        for name in selected.sorted() {
            guard !existingNames.contains(name.lowercased()) else { continue }
            _ = tagStore.addTag(name: name, categoryID: catID)
            importedCount += 1
        }

        // Remove successfully imported names from the orphaned set
        viewModel.removeOrphanedXmpTagNames(selected)
        selected.removeAll()

        // Show banner
        self.importedCount = importedCount
        withAnimation { showImportedBanner = true }
    }
}
