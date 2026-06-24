//
//  SettingsTagsPaneView.swift
//  DuckSort
//
//  The "Tags" tab of the unified Settings window.
//

import SwiftUI
import UniformTypeIdentifiers

struct SettingsTagsPaneView: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel
    @ObservedObject var tagStore: TagStore

    @State private var selectedCategoryID: UUID? = nil

    var body: some View {
        SettingsSplitLayout {
            TagsCategorySidebar(
                tagStore: tagStore,
                selectedCategoryID: $selectedCategoryID
            )
        } detail: {
            TagsDetailPanel(
                tagStore: tagStore,
                selectedCategoryID: $selectedCategoryID
            )
        }
        .onAppear {
            if selectedCategoryID == nil {
                selectedCategoryID = tagStore.categories.first?.id
            }
        }
        .onChange(of: tagStore.categories) { _, newCategories in
            if let id = selectedCategoryID, !newCategories.contains(where: { $0.id == id }) {
                selectedCategoryID = newCategories.first?.id
            }
        }
    }
}

// MARK: - Category Sidebar

private struct TagsCategorySidebar: View {
    @ObservedObject var tagStore: TagStore
    @Binding var selectedCategoryID: UUID?
    @State private var newCategoryName: String = ""
    @FocusState private var isAddFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("CATEGORIES")
                    .font(Theme.Font.caption2)
                    .tracking(0.3)
                    .foregroundStyle(Theme.Color.textSecondary)
                Spacer()
            }
            .padding(.horizontal, Theme.Space.s12)
            .padding(.top, Theme.Space.s10)
            .padding(.bottom, Theme.Space.s6)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(tagStore.categories) { category in
                        CategorySidebarRow(
                            category: category,
                            tagCount: tagStore.tags(in: category.id).count,
                            isSelected: selectedCategoryID == category.id,
                            onSelect: { selectedCategoryID = category.id },
                            onDelete: { tagStore.deleteCategory(id: category.id) }
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Rectangle()
                .fill(Theme.Color.surfaceDivider)
                .frame(height: Theme.Stroke.hairline)

            HStack(spacing: Theme.Space.s4) {
                TextField("New category", text: $newCategoryName)
                    .textFieldStyle(.plain)
                    .font(Theme.Font.subheadline)
                    .foregroundStyle(Theme.Color.textInverse)
                    .focused($isAddFieldFocused)
                    .onSubmit(commitNewCategory)

                Button(action: commitNewCategory) {
                    Image(systemName: "plus")
                        .font(.system(size: Theme.Space.s12, weight: .medium))
                        .foregroundStyle(
                            newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty
                                ? Theme.Color.surfaceStroke
                                : Theme.Color.textSecondary
                        )
                }
                .buttonStyle(.plain)
                .disabled(newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, Theme.Space.s12)
            .padding(.vertical, Theme.Space.s8)
        }
    }

    private func commitNewCategory() {
        let trimmed = newCategoryName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let newCat = tagStore.addCategory(name: trimmed)
        selectedCategoryID = newCat.id
        newCategoryName = ""
        isAddFieldFocused = false
    }
}

private struct CategorySidebarRow: View {
    let category: TagCategory
    let tagCount: Int
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: Theme.Space.s8) {
                Image(systemName: "folder")
                    .font(.system(size: Theme.Space.s10))
                    .foregroundStyle(isSelected ? Theme.Color.textInverse : Theme.Color.textSecondary)
                    .frame(width: 14)

                Text(category.name)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Theme.Color.textInverse : Theme.Color.textPrimary)
                    .lineLimit(1)

                Spacer()

                if tagCount > 0 {
                    Text("\(tagCount)")
                        .font(Theme.Font.footnote)
                        .foregroundStyle(isSelected ? Theme.Color.textInverse.opacity(0.65) : Theme.Color.textTertiary)
                }
            }
            .padding(.horizontal, Theme.Space.s10)
            .padding(.vertical, Theme.Space.s8)
            .background(
                isSelected
                    ? Theme.Color.accent
                    : (isHovered ? Theme.Color.overlaySofter : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovered = hovering }
        }
        .contextMenu {
            Button("Delete Category", role: .destructive, action: onDelete)
        }
    }
}

// MARK: - Tags Detail Panel

private struct TagsDetailPanel: View {
    @ObservedObject var tagStore: TagStore
    @Binding var selectedCategoryID: UUID?

    private var selectedCategory: TagCategory? {
        guard let id = selectedCategoryID else { return nil }
        return tagStore.categories.first(where: { $0.id == id })
    }

    private var tagsInCategory: [CustomTag] {
        guard let id = selectedCategoryID else { return [] }
        return tagStore.tags(in: id)
    }

    var body: some View {
        if let category = selectedCategory {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Text("Tag Name")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Color.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, Theme.Space.s16)

                    Text("Hotkey")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Color.textTertiary)
                        .frame(width: 110, alignment: .center)

                    Text("Color")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Color.textTertiary)
                        .frame(width: 64, alignment: .center)
                        .padding(.trailing, Theme.Space.s16)
                }
                .padding(.vertical, Theme.Space.s8)
                .background(Theme.Color.surfaceBase)

                Rectangle()
                    .fill(Theme.Color.surfaceRaised)
                    .frame(height: Theme.Stroke.hairline)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(tagsInCategory.enumerated()), id: \.element.id) { index, tag in
                            TagTableRow(
                                tag: tag,
                                rowIndex: index,
                                tagStore: tagStore
                            )
                        }

                        AddTagRow(
                            onCommit: { name, colorHex in
                                commitNewTag(for: category, name: name, colorHex: colorHex)
                            }
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            VStack {
                Spacer()
                Image(systemName: "tag")
                    .font(Theme.Font.iconLarge)
                    .foregroundStyle(Theme.Color.surfaceStroke)
                Text("Select a category")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .padding(.top, Theme.Space.s6)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func commitNewTag(for category: TagCategory, name: String, colorHex: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        tagStore.addTag(name: trimmed, categoryID: category.id, colorHex: colorHex)
    }
}

// MARK: - Tag Table Row

private struct TagTableRow: View {
    let tag: CustomTag
    let rowIndex: Int
    @ObservedObject var tagStore: TagStore
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            TagNameField(tag: tag, tagStore: tagStore)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, Theme.Space.s16)

            ShortcutRecorderView(hotkey: Binding(
                get: { tag.hotkey },
                set: { newValue in
                    var updated = tag
                    updated.hotkey = newValue
                    tagStore.updateTag(updated)
                }
            ))
            .frame(width: 110, alignment: .center)

            HStack {
                Spacer()
                ColorPicker("", selection: Binding(
                    get: { tag.color },
                    set: { newColor in
                        var updated = tag
                        updated.colorHex = newColor.toHex() ?? tag.colorHex
                        tagStore.updateTag(updated)
                    }
                ), supportsOpacity: false)
                .labelsHidden()
                .frame(width: 28, height: 20)
                Spacer()
            }
            .frame(width: 64)
            .padding(.trailing, isHovered ? 0 : Theme.Space.s16)

            if isHovered {
                Button(action: { tagStore.deleteTag(id: tag.id) }) {
                    Image(systemName: "minus.circle")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.Color.danger)
                }
                .buttonStyle(.plain)
                .padding(.trailing, Theme.Space.s16)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .frame(height: 36)
        .background(rowIndex % 2 == 1 ? Theme.Color.overlaySofter : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovered = hovering }
        }
    }
}

// MARK: - Inline-editable tag name

private struct TagNameField: View {
    let tag: CustomTag
    @ObservedObject var tagStore: TagStore
    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("", text: Binding(
            get: { tag.name },
            set: { newName in
                var updated = tag
                updated.name = newName
                tagStore.updateTag(updated)
            }
        ))
        .textFieldStyle(.plain)
        .font(Theme.Font.body)
        .foregroundStyle(Theme.Color.textInverse)
        .padding(.horizontal, Theme.Space.s6)
        .padding(.vertical, Theme.Space.s4)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.s)
                .stroke(
                    isFocused || isHovered ? Theme.Color.accent.opacity(0.6) : Color.clear,
                    lineWidth: Theme.Stroke.hairline
                )
        )
        .focused($isFocused)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) { isHovered = hovering }
        }
    }
}

// MARK: - Add Tag Row (footer)

private struct AddTagRow: View {
    let onCommit: (_ name: String, _ colorHex: String) -> Void
    @State private var name: String = ""
    @State private var color: Color = {
        let palette = [
            "#FF6B6B", "#FFA94D", "#FFD43B", "#4ECDC4",
            "#4D96FF", "#A78BFA", "#F472B6", "#6BCB77",
            "#38BDF8", "#FB923C", "#A7F3D0", "#C084FC"
        ]
        return Color(hex: palette.randomElement() ?? "#4D96FF") ?? Theme.Color.accent
    }()
    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var colorHex: String {
        color.toHex() ?? "#4D96FF"
    }

    private let palette = [
        "#FF6B6B", "#FFA94D", "#FFD43B", "#4ECDC4",
        "#4D96FF", "#A78BFA", "#F472B6", "#6BCB77",
        "#38BDF8", "#FB923C", "#A7F3D0", "#C084FC"
    ]

    var body: some View {
        HStack(spacing: 0) {
            TextField("Add new tag…", text: $name)
                .textFieldStyle(.plain)
                .font(Theme.Font.body)
                .foregroundStyle(canSubmit ? Theme.Color.textInverse : Theme.Color.textTertiary)
                .onSubmit(submit)
                .focused($isFocused)
                .padding(.leading, 22)
                .frame(maxWidth: .infinity, alignment: .leading)

            if canSubmit {
                ColorPicker("", selection: $color, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 28, height: 20)
                    .padding(.trailing, Theme.Space.s8)

                Button(action: submit) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.Color.accent)
                }
                .buttonStyle(.plain)
                .padding(.trailing, Theme.Space.s14)
            }
        }
        .frame(height: 36)
        .contentShape(Rectangle())
        .onTapGesture { isFocused = true }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) { isHovered = hovering }
        }
        .background(isHovered ? Theme.Color.overlaySofter : Color.clear)
    }

    private func submit() {
        guard canSubmit else { return }
        onCommit(name, colorHex)
        name = ""
        color = Color(hex: palette.randomElement() ?? "#4D96FF") ?? Theme.Color.accent
    }
}
