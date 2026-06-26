//
//  SettingsTagsPaneView.swift
//  DuckSort
//
//  The "Tags" tab of the unified Settings window. Single-column layout:
//  pack switcher / creator at the top, then the per-category tag editor
//  underneath. Categories are shown inline in the editor rather than
//  in a left sidebar, so the window has more breathing room and
//  resizes naturally.
//

import SwiftUI
import UniformTypeIdentifiers

struct SettingsTagsPaneView: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel
    @ObservedObject var tagStore: TagStore

    var body: some View {
        VStack(spacing: 0) {
            TagPacksHeader(viewModel: viewModel)
            Rectangle()
                .fill(Theme.Color.surfaceDivider)
                .frame(height: Theme.Stroke.hairline)

            TagsDetailPanel(
                tagStore: tagStore,
                viewModel: viewModel
            )
        }
    }
}

// MARK: - Pack switcher header

private struct TagPacksHeader: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel

    @State private var showingNewPack = false
    @State private var showingSwitchConfirm = false
    @State private var pendingSwitchID: String? = nil
    @State private var pendingDeleteID: String? = nil
    @State private var showingDeleteConfirm = false
    @State private var pendingResetID: String? = nil
    @State private var showingResetConfirm = false
    @State private var renameTarget: TagPackState? = nil
    @State private var renameText: String = ""
    @State private var styleTarget: TagPackState? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s8) {
            HStack(spacing: Theme.Space.s8) {
                Text("TAG PACKS")
                    .font(Theme.Font.caption2)
                    .tracking(0.3)
                    .foregroundStyle(Theme.Color.textSecondary)
                Spacer()
                Button {
                    showingNewPack = true
                } label: {
                    Label("New Pack…", systemImage: "plus")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderless)
                .font(Theme.Font.caption)
                Button {
                    viewModel.importPack()
                } label: {
                    Label("Import…", systemImage: "square.and.arrow.down")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderless)
                .font(Theme.Font.caption)
                Button(role: .destructive) {
                    let activeID = UserPreferences.shared.activeTagPackID
                    pendingDeleteID = activeID
                    showingDeleteConfirm = true
                } label: {
                    Label("Delete Active Pack", systemImage: "trash")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderless)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.danger)
                .disabled(viewModel.packLibrary.isBuiltIn(UserPreferences.shared.activeTagPackID))
            }
            .padding(.horizontal, Theme.Space.s16)
            .padding(.top, Theme.Space.s10)
            .padding(.bottom, Theme.Space.s8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Space.s8) {
                    ForEach(viewModel.packLibrary.packs) { state in
                        TagPackMiniCard(
                            state: state,
                            isActive: state.id == UserPreferences.shared.activeTagPackID,
                            onActivate: {
                                pendingSwitchID = state.id
                                showingSwitchConfirm = true
                            },
                            onRename: {
                                renameText = state.name
                                renameTarget = state
                            },
                            onReset: {
                                pendingResetID = state.id
                                showingResetConfirm = true
                            },
                            onDuplicate: {
                                if let copy = viewModel.duplicatePack(id: state.id,
                                                                         newName: "\(state.name) Copy") {
                                    viewModel.switchTagPack(id: copy.id)
                                }
                            },
                            onDelete: {
                                pendingDeleteID = state.id
                                showingDeleteConfirm = true
                            },
                            onExport: {
                                viewModel.exportPack(id: state.id)
                            },
                            onRestyle: {
                                styleTarget = state
                            }
                        )
                    }
                }
                .padding(.horizontal, Theme.Space.s16)
                .padding(.vertical, 3)
                .padding(.bottom, Theme.Space.s14)
            }

            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .foregroundStyle(Theme.Color.textTertiary)
                    .font(Theme.Font.caption2)
                Text("Tip: ⌘1–⌘9 from the Tag Packs menu (or here) swaps the active pack. Your edits to a pack are remembered next time you switch back.")
                    .font(Theme.Font.caption2)
                    .foregroundStyle(Theme.Color.textTertiary)
            }
            .padding(.horizontal, Theme.Space.s16)
            .padding(.bottom, Theme.Space.s10)
        }
        .background(Theme.Color.surfaceBase)
        .sheet(isPresented: $showingNewPack) {
            NewPackSheet(viewModel: viewModel, isPresented: $showingNewPack)
        }
        .sheet(item: $renameTarget) { target in
            RenamePackSheet(
                currentName: target.name,
                isPresented: Binding(
                    get: { renameTarget != nil },
                    set: { if !$0 { renameTarget = nil } }
                ),
                onCommit: { newName in
                    viewModel.renamePack(id: target.id, to: newName)
                    renameTarget = nil
                }
            )
        }
        .sheet(item: $styleTarget) { target in
            PackStyleSheet(
                state: target,
                isPresented: Binding(
                    get: { styleTarget != nil },
                    set: { if !$0 { styleTarget = nil } }
                ),
                onCommit: { systemImage, accentColor in
                    viewModel.restylePack(id: target.id,
                                          systemImage: systemImage,
                                          accentColor: accentColor)
                    styleTarget = nil
                }
            )
        }
        .confirmationDialog(
            pendingSwitchLabel,
            isPresented: $showingSwitchConfirm,
            titleVisibility: .visible
        ) {
            Button("Switch") {
                if let id = pendingSwitchID {
                    viewModel.switchTagPack(id: id)
                }
                pendingSwitchID = nil
            }
            Button("Cancel", role: .cancel) { pendingSwitchID = nil }
        } message: {
            Text("Saves your edits to the current pack, then loads the chosen pack.")
        }
        .confirmationDialog(
            "Delete \(pendingDeleteName)?",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let id = pendingDeleteID {
                    viewModel.deletePack(id: id)
                }
                pendingDeleteID = nil
            }
            Button("Cancel", role: .cancel) { pendingDeleteID = nil }
        } message: {
            Text("This removes the pack and its saved state. The active pack switches to the default if needed.")
        }
        .confirmationDialog(
            "Reset \(pendingResetName) to factory defaults?",
            isPresented: $showingResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) {
                if let id = pendingResetID {
                    viewModel.resetPack(id: id)
                }
                pendingResetID = nil
            }
            Button("Cancel", role: .cancel) { pendingResetID = nil }
        } message: {
            Text("Replaces the pack's categories and tags with its built-in defaults. Any custom edits are lost.")
        }
    }

    private var pendingSwitchLabel: String {
        guard let id = pendingSwitchID,
              let pack = viewModel.packLibrary.state(for: id)
        else { return "" }
        return "Switch to \(pack.name)?"
    }

    private var pendingDeleteName: String {
        guard let id = pendingDeleteID,
              let pack = viewModel.packLibrary.state(for: id)
        else { return "pack" }
        return pack.name
    }

    private var pendingResetName: String {
        guard let id = pendingResetID,
              let pack = viewModel.packLibrary.state(for: id)
        else { return "pack" }
        return pack.name
    }
}

private struct TagPackMiniCard: View {
    let state: TagPackState
    let isActive: Bool
    let onActivate: () -> Void
    let onRename: () -> Void
    let onReset: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    let onExport: () -> Void
    let onRestyle: () -> Void

    var body: some View {
        Button(action: onActivate) {
            VStack(alignment: .leading, spacing: Theme.Space.s10) {
                HStack(spacing: Theme.Space.s10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: Theme.Radius.m)
                            .fill(Color(hex: state.accentColor)?.opacity(0.18) ?? Theme.Color.accent.opacity(0.18))
                            .frame(width: 36, height: 36)
                        Image(systemName: state.systemImage)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color(hex: state.accentColor) ?? .accentColor)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: Theme.Space.s6) {
                            Text(state.name)
                                .font(Theme.Font.bodyBold)
                                .foregroundStyle(Theme.Color.textInverse)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            if isActive {
                                Text("ACTIVE")
                                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                                    .tracking(0.5)
                                    .foregroundStyle(Theme.Color.textInverse)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule().fill(Theme.Color.success)
                                    )
                                    .fixedSize()
                            }
                            if !state.isBuiltIn {
                                Text("CUSTOM")
                                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                                    .tracking(0.5)
                                    .foregroundStyle(Theme.Color.textInverse)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule().fill(Theme.Color.accent)
                                    )
                                    .fixedSize()
                            }
                        }
                        Text("\(state.tags.count) tags · \(state.categories.count) categories")
                            .font(Theme.Font.caption2)
                            .foregroundStyle(Theme.Color.textSecondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                Menu {
                    Button("Activate", action: onActivate)
                    Button("Export…", action: onExport)
                    Divider()
                    Button("Reset to Factory", action: onReset)
                    Button("Duplicate", action: onDuplicate)
                    if !state.isBuiltIn {
                        Divider()
                        Button("Logo & Color…", action: onRestyle)
                        Button("Rename…", action: onRename)
                        Button("Delete Pack", role: .destructive, action: onDelete)
                    } else {
                        Divider()
                        Button("Duplicate to Edit Logo", action: onDuplicate)
                    }
                } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 16))
                            .foregroundStyle(Theme.Color.textSecondary)
                            .padding(4)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
            }
            .padding(.horizontal, Theme.Space.s12)
            .padding(.vertical, Theme.Space.s10)
            .frame(width: 280, height: 72, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.m)
                    .fill(isActive
                          ? Theme.Color.accent.opacity(0.12)
                          : Theme.Color.surfaceRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.m)
                    .stroke(isActive ? Theme.Color.accent : Theme.Color.surfaceDivider,
                            lineWidth: isActive ? 2 : Theme.Stroke.hairline)
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.m))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tags detail panel (full-width)

private struct TagsDetailPanel: View {
    @ObservedObject var tagStore: TagStore
    @ObservedObject var viewModel: PhotoLibraryViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Categories in the active pack. Inline-edit names, hotkeys, and colors below.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .padding(.horizontal, Theme.Space.s20)
                    .padding(.vertical, Theme.Space.s10)
            }
            .background(Theme.Color.surfaceBase)

            Rectangle()
                .fill(Theme.Color.surfaceRaised)
                .frame(height: Theme.Stroke.hairline)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Space.s16) {
                    ForEach(tagStore.categories) { category in
                        CategorySection(
                            category: category,
                            tags: tagStore.tags(in: category.id),
                            tagStore: tagStore
                        )
                    }

                    Button {
                        viewModel.tagStore.addCategory(name: "New Category")
                    } label: {
                        Label("Add Category", systemImage: "plus.circle")
                            .padding(.horizontal, Theme.Space.s8)
                            .padding(.vertical, Theme.Space.s6)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.Radius.m)
                                    .stroke(Theme.Color.surfaceDivider,
                                            style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, Theme.Space.s20)
                }
                .padding(.vertical, Theme.Space.s14)
            }
        }
    }
}

private struct CategorySection: View {
    let category: TagCategory
    let tags: [CustomTag]
    @ObservedObject var tagStore: TagStore

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s8) {
            HStack(spacing: Theme.Space.s8) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(Color.accentColor.opacity(0.6))
                Text(category.name)
                    .font(Theme.Font.bodyBold)
                    .foregroundStyle(Theme.Color.textInverse)
                Text("\(tags.count)")
                    .font(Theme.Font.caption2)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(Theme.Color.surfaceRaised)
                    )
                Spacer()
                if tags.isEmpty {
                    Button(role: .destructive) {
                        tagStore.deleteCategory(id: category.id)
                    } label: {
                        Image(systemName: "minus.circle")
                            .foregroundStyle(Theme.Color.danger)
                    }
                    .buttonStyle(.borderless)
                    .help("Remove empty category")
                }
            }
            .padding(.horizontal, Theme.Space.s20)

            if tags.isEmpty {
                Text("No tags yet in this category.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .padding(.horizontal, Theme.Space.s20)
                    .padding(.bottom, Theme.Space.s6)
            } else {
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 220), spacing: Theme.Space.s8)
                ], alignment: .leading, spacing: Theme.Space.s6) {
                    ForEach(tags) { tag in
                        TagChip(tag: tag, tagStore: tagStore)
                    }
                }
                .padding(.horizontal, Theme.Space.s20)
                .padding(.bottom, Theme.Space.s6)
            }

            HStack(spacing: Theme.Space.s8) {
                Button {
                    tagStore.addTag(name: "New Tag", categoryID: category.id)
                } label: {
                    Label("Add Tag to \(category.name)", systemImage: "plus")
                        .font(Theme.Font.caption)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .padding(.horizontal, Theme.Space.s20)
                .padding(.bottom, Theme.Space.s10)
            }
        }
    }
}

private struct TagChip: View {
    let tag: CustomTag
    @ObservedObject var tagStore: TagStore
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Theme.Space.s12) {
            TagColorPicker(tag: tag, tagStore: tagStore)
                .frame(width: 26, height: 26)

            TextField("", text: Binding(
                get: { tag.name },
                set: { newName in
                    var updated = tag
                    updated.name = newName
                    tagStore.updateTag(updated)
                }
            ))
            .textFieldStyle(.plain)
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.Color.textInverse)
            .padding(.leading, 2)
            .frame(maxWidth: 140)

            ShortcutRecorderView(
                hotkey: Binding(
                    get: { tag.hotkey },
                    set: { newValue in
                        var updated = tag
                        updated.hotkey = newValue
                        tagStore.updateTag(updated)
                    }
                ),
                validationMessage: { proposed in tagHotkeyConflict(proposed, for: tag, in: tagStore) }
            )
            .controlSize(.mini)
            .frame(width: 64)

            if isHovered {
                Button(role: .destructive) {
                    tagStore.deleteTag(id: tag.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.Color.textSecondary)
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, Theme.Space.s12)
        .padding(.vertical, Theme.Space.s8)
        .frame(minHeight: 36)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.m)
                .fill(Theme.Color.surfaceRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.m)
                .stroke(Theme.Color.surfaceDivider, lineWidth: Theme.Stroke.hairline)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) { isHovered = hovering }
        }
    }

    private func tagHotkeyConflict(_ hotkey: String, for tag: CustomTag, in tagStore: TagStore) -> String? {
        if let reason = TagHotkeyRules.reservedReason(for: hotkey) {
            return "Used by \(reason)"
        }
        if let other = tagStore.tags.first(where: { $0.id != tag.id && $0.hotkey == hotkey }) {
            return "Used by \(other.name)"
        }
        return nil
    }
}

private struct TagColorPicker: View {
    let tag: CustomTag
    @ObservedObject var tagStore: TagStore
    @State private var isShowingPicker = false

    var body: some View {
        Button {
            isShowingPicker = true
        } label: {
            RoundedRectangle(cornerRadius: Theme.Radius.s)
                .fill(tag.color)
                .frame(width: 20, height: 20)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.s)
                        .stroke(.white.opacity(0.22), lineWidth: 1)
                )
                .shadow(color: tag.color.opacity(0.35), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.s))
        .help("Change color")
        .popover(isPresented: $isShowingPicker, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: Theme.Space.s8) {
                Text(tag.name)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .lineLimit(1)
                ColorPicker("Color", selection: Binding(
                    get: { tag.color },
                    set: { newColor in
                        var updated = tag
                        updated.colorHex = newColor.toHex() ?? tag.colorHex
                        tagStore.updateTag(updated)
                    }
                ), supportsOpacity: false)
                .labelsHidden()
            }
            .padding(Theme.Space.s12)
            .frame(width: 160)
            .background(Theme.Color.surfaceBase)
        }
    }
}

// MARK: - Sheets

private struct NewPackSheet: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel
    @Binding var isPresented: Bool

    @State private var name: String = ""
    @State private var basedOnTemplateID: String = TagPackTemplate.defaultTemplateID
    @State private var draftSymbol: String = TagPackTemplate.general.systemImage
    @State private var draftAccent: Color = Color(hex: TagPackTemplate.general.accentColor) ?? Theme.Color.accent

    private let templates = TagPackTemplate.allTemplates

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s14) {
            Text("New Tag Pack")
                .font(Theme.Font.title)
                .foregroundStyle(Theme.Color.textInverse)

            Text("Pick a starting point. The pack will be added to your library and activated immediately.")
                .font(Theme.Font.subheadline)
                .foregroundStyle(Theme.Color.textSecondary)

            VStack(alignment: .leading, spacing: Theme.Space.s6) {
                Text("Name")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.textSecondary)
                TextField("e.g. Studio Portraits", text: $name)
                    .textFieldStyle(.plain)
                    .font(Theme.Font.body)
                    .padding(.horizontal, Theme.Space.s10)
                    .padding(.vertical, Theme.Space.s8)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.m)
                            .fill(Theme.Color.surfaceRaised)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.m)
                            .stroke(Theme.Color.surfaceDivider, lineWidth: Theme.Stroke.hairline)
                    )
            }

            VStack(alignment: .leading, spacing: Theme.Space.s6) {
                Text("Start from")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.textSecondary)
                Picker("Template", selection: $basedOnTemplateID) {
                    ForEach(templates) { template in
                        Text(template.name).tag(template.id)
                    }
                    Text("Empty").tag("__empty__")
                }
                .pickerStyle(.menu)
            }
            .onChange(of: basedOnTemplateID) { _, newValue in
                guard let template = TagPackTemplate.template(id: newValue) else {
                    draftSymbol = "tag"
                    draftAccent = Theme.Color.accent
                    return
                }
                draftSymbol = template.systemImage
                draftAccent = Color(hex: template.accentColor) ?? Theme.Color.accent
            }

            VStack(alignment: .leading, spacing: Theme.Space.s6) {
                Text("Logo & Color")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.textSecondary)
                HStack(spacing: Theme.Space.s8) {
                    Image(systemName: draftSymbol.isEmpty ? "questionmark.circle" : draftSymbol)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(draftAccent)
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.s)
                                .fill(draftAccent.opacity(0.18))
                        )
                    TextField("SF Symbol", text: $draftSymbol)
                        .textFieldStyle(.roundedBorder)
                    Picker("Suggestions", selection: $draftSymbol) {
                        ForEach(PackSymbolCatalog.allSymbols, id: \.self) { symbol in
                            Label(symbol, systemImage: symbol).tag(symbol)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    ColorPicker("", selection: $draftAccent, supportsOpacity: false)
                        .labelsHidden()
                        .frame(width: 32)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                Button("Create & Activate") { commit() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(Theme.Color.accent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(Theme.Space.s24)
        .frame(width: 460)
        .background(Theme.Color.surfaceBase)
    }

    private func commit() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let symbol = draftSymbol.trimmingCharacters(in: .whitespacesAndNewlines)
        let icon = symbol.isEmpty ? "tag" : symbol
        let accent = draftAccent.toHex() ?? "#4A90E2"
        if basedOnTemplateID == "__empty__" {
            _ = viewModel.createPack(named: trimmed, systemImage: icon, accentColor: accent)
        } else {
            _ = viewModel.createPack(named: trimmed, basedOnTemplateID: basedOnTemplateID, systemImage: icon, accentColor: accent)
        }
        // Activate whatever pack was just created (last in the list).
        if let last = viewModel.packLibrary.packs.last {
            viewModel.switchTagPack(id: last.id)
        }
        isPresented = false
    }
}

private struct RenamePackSheet: View {
    let currentName: String
    @Binding var isPresented: Bool
    let onCommit: (String) -> Void

    @State private var draft: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s14) {
            Text("Rename Pack")
                .font(Theme.Font.title)
                .foregroundStyle(Theme.Color.textInverse)

            TextField("Pack name", text: $draft)
                .textFieldStyle(.plain)
                .font(Theme.Font.body)
                .padding(.horizontal, Theme.Space.s10)
                .padding(.vertical, Theme.Space.s8)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.m)
                        .fill(Theme.Color.surfaceRaised)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.m)
                        .stroke(Theme.Color.surfaceDivider, lineWidth: Theme.Stroke.hairline)
                )
                .onAppear { draft = currentName }

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                Button("Save") {
                    onCommit(draft.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Theme.Color.accent)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(Theme.Space.s24)
        .frame(width: 420)
        .background(Theme.Color.surfaceBase)
    }
}

// MARK: - Pack style (logo + accent color)

/// Curated catalog of SF Symbols that read well as a tag-pack logo. Grouped
/// by intent so the picker stays scannable. Users can also type or paste any SF
/// Symbol name in the search field to use one not in the catalog.
private enum PackSymbolCatalog {
    struct Group: Identifiable {
        let id = UUID()
        let title: String
        let symbols: [String]
    }

    static let groups: [Group] = [
        Group(title: "People & Places", symbols: [
            "person.crop.circle", "person.2", "person.crop.square",
            "house", "building.2", "globe", "map", "mountain.2"
        ]),
        Group(title: "Moments & Mood", symbols: [
            "heart", "heart.fill", "star", "star.fill", "sparkles",
            "sun.max", "moon.stars", "cloud.rain", "leaf", "flame"
        ]),
        Group(title: "Activities", symbols: [
            "camera", "camera.fill", "video", "mic", "music.note",
            "sportscourt", "figure.run", "bicycle", "sailboat",
            "airplane", "car", "tram"
        ]),
        Group(title: "Objects & Work", symbols: [
            "tag", "tag.fill", "folder", "tray.full", "shippingbox",
            "briefcase", "hammer", "wrench.adjustable", "paintpalette",
            "pencil.and.list.clipboard", "doc.text", "calendar"
        ]),
        Group(title: "Tech & Media", symbols: [
            "iphone", "macbook", "desktopcomputer", "tv", "gamecontroller",
            "headphones", "antenna.radiowaves.left.and.right",
            "wifi", "bolt", "bubble.left.and.bubble.right"
        ])
    ]

    /// Flat list of every curated symbol — used for instant search.
    static var allSymbols: [String] {
        groups.flatMap { $0.symbols }
    }
}

private struct PackStyleSheet: View {
    let state: TagPackState
    @Binding var isPresented: Bool
    let onCommit: (_ systemImage: String, _ accentColor: String) -> Void

    @State private var draftSymbol: String = ""
    @State private var draftAccent: Color
    @State private var searchQuery: String = ""

    init(state: TagPackState,
         isPresented: Binding<Bool>,
         onCommit: @escaping (String, String) -> Void) {
        self.state = state
        self._isPresented = isPresented
        self.onCommit = onCommit
        _draftSymbol = State(initialValue: state.systemImage)
        _draftAccent = State(initialValue: Color(hex: state.accentColor) ?? Theme.Color.accent)
    }

    private var filteredGroups: [PackSymbolCatalog.Group] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return PackSymbolCatalog.groups }
        return PackSymbolCatalog.groups.compactMap { group in
            let matches = group.symbols.filter { $0.lowercased().contains(q) }
            return matches.isEmpty ? nil : PackSymbolCatalog.Group(title: group.title, symbols: matches)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Logo & Color")
                        .font(Theme.Font.headline)
                        .foregroundStyle(Theme.Color.textPrimary)
                    Text("Choose from the grid, or type any SF Symbol name for “\(state.name)”.")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Color.textSecondary)
                }
                Spacer()
                preview
            }

            Divider().overlay(Theme.Color.surfaceDivider)

            HStack(spacing: Theme.Space.s12) {
                Text("Accent")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .frame(width: 64, alignment: .leading)
                ColorPicker(selection: $draftAccent, supportsOpacity: false) {
                    HStack(spacing: Theme.Space.s8) {
                        Capsule()
                            .fill(draftAccent)
                            .frame(width: 22, height: 22)
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
                            )
                        Text(draftAccent.toHex() ?? "—")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Color.textInverse)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.Color.textTertiary)
                    }
                    .padding(.horizontal, Theme.Space.s10)
                    .padding(.vertical, Theme.Space.s6)
                    .background(
                        Capsule().fill(Theme.Color.surfaceRaised)
                    )
                    .overlay(
                        Capsule()
                            .stroke(Theme.Color.surfaceDivider, lineWidth: Theme.Stroke.hairline)
                    )
                }
                .labelsHidden()
                .help("Click to choose a color from the system picker")

                Spacer()
            }

            VStack(alignment: .leading, spacing: Theme.Space.s8) {
                Text("Logo")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.textSecondary)

                HStack(spacing: Theme.Space.s8) {
                    Image(systemName: draftSymbol.isEmpty ? "questionmark.circle" : draftSymbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(draftAccent)
                        .frame(width: 36, height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.s)
                                .fill(draftAccent.opacity(0.18))
                        )
                    TextField("Custom SF Symbol name, e.g. leaf.fill", text: $draftSymbol)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.regular)
                        .font(Theme.Font.caption)
                        .onSubmit { commit() }
                }

                HStack(spacing: Theme.Space.s8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Theme.Color.textTertiary)
                        .font(Theme.Font.caption2)
                    TextField("Search built-in logo choices", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .font(Theme.Font.caption)
                    if !searchQuery.isEmpty {
                        Button {
                            searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Theme.Color.textTertiary)
                                .font(Theme.Font.caption2)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Theme.Space.s8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.s)
                        .fill(Theme.Color.surfaceRaised)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.s)
                        .stroke(Theme.Color.surfaceDivider, lineWidth: Theme.Stroke.hairline)
                )
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Space.s12) {
                    ForEach(filteredGroups) { group in
                        VStack(alignment: .leading, spacing: Theme.Space.s6) {
                            Text(group.title)
                                .font(Theme.Font.caption2)
                                .tracking(0.3)
                                .foregroundStyle(Theme.Color.textTertiary)
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 8),
                                      alignment: .leading,
                                      spacing: 6) {
                                ForEach(group.symbols, id: \.self) { symbol in
                                    symbolButton(symbol)
                                }
                            }
                        }
                    }
                    if filteredGroups.isEmpty {
                        Text("No curated matches. Type any SF Symbol name above (e.g. “leaf.fill”, “camera.macro”).")
                            .font(Theme.Font.caption2)
                            .foregroundStyle(Theme.Color.textTertiary)
                            .padding(.top, Theme.Space.s8)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 280)
            .scrollIndicators(.visible)

            HStack {
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") { commit() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(draftAccent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(draftSymbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(Theme.Space.s20)
        .frame(width: 520, height: 560)
        .background(Theme.Color.surfaceBase)
    }

    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Radius.m)
                .fill(draftAccent.opacity(0.18))
                .frame(width: 48, height: 48)
            Image(systemName: draftSymbol.isEmpty ? "questionmark.circle" : draftSymbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(draftAccent)
        }
    }

    private func symbolButton(_ symbol: String) -> some View {
        let isSelected = draftSymbol == symbol
        return Button {
            draftSymbol = symbol
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isSelected ? .white : Theme.Color.textPrimary)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.s)
                        .fill(isSelected ? draftAccent : Theme.Color.surfaceRaised)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.s)
                        .stroke(isSelected ? draftAccent : Theme.Color.surfaceDivider,
                                lineWidth: isSelected ? 1.5 : Theme.Stroke.hairline)
                )
        }
        .buttonStyle(.plain)
        .help(symbol)
    }

    private func commit() {
        let trimmed = draftSymbol.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let hex = draftAccent.toHex() ?? state.accentColor
        onCommit(trimmed, hex)
    }
}
