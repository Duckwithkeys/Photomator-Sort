//
//  SettingsShortcutsPaneView.swift
//  DuckSort
//
//  The "Shortcuts" tab of the unified Settings window.
//

import SwiftUI

private enum ShortcutsSection: String, CaseIterable, Identifiable {
    case appActions    = "App Actions"
    case culling       = "Culling Control"
    case tagHotkeys    = "Tag Hotkeys"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .appActions: return "gearshape"
        case .culling:    return "arrow.left.arrow.right"
        case .tagHotkeys: return "tag"
        }
    }
}

struct SettingsShortcutsPaneView: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel
    @State private var selectedSection: ShortcutsSection = .appActions

    var body: some View {
        SettingsSplitLayout {
            ShortcutsSidebarIndex(
                selectedSection: $selectedSection,
                tagHotkeysAvailable: !viewModel.tagStore.tags.isEmpty
            )
        } detail: {
            ShortcutsDetailContent(
                viewModel: viewModel,
                section: selectedSection
            )
        }
    }
}

// MARK: - Left sidebar: section index

private struct ShortcutsSidebarIndex: View {
    @Binding var selectedSection: ShortcutsSection
    let tagHotkeysAvailable: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("SECTIONS")
                    .font(Theme.Font.caption2)
                    .tracking(0.3)
                    .foregroundStyle(Theme.Color.textSecondary)
                Spacer()
            }
            .padding(.horizontal, Theme.Space.s12)
            .padding(.top, Theme.Space.s10)
            .padding(.bottom, Theme.Space.s6)

            ForEach(ShortcutsSection.allCases) { section in
                let isDisabled = section == .tagHotkeys && !tagHotkeysAvailable
                shortcutIndexRow(
                    icon: section.systemImage,
                    label: section.rawValue,
                    isSelected: selectedSection == section,
                    isDisabled: isDisabled
                ) {
                    guard !isDisabled else { return }
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedSection = section
                    }
                }
            }

            Spacer()
        }
    }

    @ViewBuilder
    private func shortcutIndexRow(
        icon: String,
        label: String,
        isSelected: Bool,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.s8) {
                Image(systemName: icon)
                    .font(.system(size: Theme.Space.s10))
                    .foregroundStyle(isSelected ? Theme.Color.textInverse : Theme.Color.textSecondary)
                    .frame(width: 14)
                Text(label)
                    .font(.system(size: 13, weight: isSelected ? .bold : .regular))
                    .foregroundStyle(isSelected ? Theme.Color.textInverse : Theme.Color.textPrimary)
                Spacer()
            }
            .padding(.horizontal, Theme.Space.s10)
            .padding(.vertical, Theme.Space.s8)
            .background(
                isSelected ? Theme.Color.accent : Color.clear
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1.0)
    }
}

// MARK: - Right detail panel

private struct ShortcutsDetailContent: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel
    let section: ShortcutsSection

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                switch section {
                case .appActions:
                    ShortcutsSectionHeader(title: "APP ACTIONS")

                    ShortcutEditableRow(label: "Toggle JPEG Only Mode", hotkey: $viewModel.jpegOnlyHotkey)

                case .culling:
                    ShortcutsSectionHeader(title: "CULLING CONTROL")

                    ShortcutStaticRow(label: "Toggle Selection",       shortcut: "S")
                    ShortcutDividerRow()
                    ShortcutStaticRow(label: "Clear All Tags",         shortcut: "0")
                    ShortcutDividerRow()
                    ShortcutStaticRow(label: "Open / Close Viewer",    shortcut: "Space / Return")
                    ShortcutDividerRow()
                    ShortcutStaticRow(label: "Close Viewer",           shortcut: "Esc")
                    ShortcutDividerRow()
                    ShortcutStaticRow(label: "Navigate Photos",        shortcut: "← → ↑ ↓")
                    ShortcutDividerRow()
                    ShortcutStaticRow(label: "Next / Prev Category",   shortcut: "[ / ]")
                    ShortcutDividerRow()
                    ShortcutStaticRow(label: "Select Visible (Grid)",  shortcut: "⌘A")
                    ShortcutDividerRow()
                    ShortcutStaticRow(label: "Flag / Reject / Unflag", shortcut: "Z / X / U")
                    ShortcutDividerRow()
                    ShortcutStaticRow(label: "Set Rating",             shortcut: "1 – 5")

                case .tagHotkeys:
                    ShortcutsSectionHeader(title: "TAG HOTKEYS")
                    let allTags = viewModel.tagStore.tags
                    if allTags.isEmpty {
                        Text("No tags yet. Create tags in the Tags tab to assign hotkeys.")
                            .font(Theme.Font.body)
                            .foregroundStyle(Theme.Color.textTertiary)
                            .padding(.horizontal, Theme.Space.s16)
                            .padding(.vertical, Theme.Space.s12)
                    } else {
                        let groups = ShortcutsDetailContent.groupedByCategory(
                            allTags,
                            categoryName: { viewModel.tagStore.categoryName(id: $0) ?? "Uncategorized" }
                        )
                        ForEach(Array(groups.enumerated()), id: \.offset) { groupIndex, group in
                            if groupIndex > 0 { ShortcutDividerRow() }
                            ShortcutsSectionHeader(title: group.categoryName.uppercased())

                            ForEach(Array(group.tags.enumerated()), id: \.element.id) { tagIndex, tag in
                                if tagIndex > 0 { ShortcutDividerRow() }
                                TagHotkeyRow(tag: tag, tagStore: viewModel.tagStore)
                            }
                        }
                    }
                }

                Spacer().frame(height: 20)
            }
        }
        .background(Theme.Color.surfaceBase)
    }
}

// MARK: - Reusable row components

private struct ShortcutsSectionHeader: View {
    let title: String
    var body: some View {
        HStack {
            Text(title)
                .font(Theme.Font.caption2)
                .tracking(0.3)
                .foregroundStyle(Theme.Color.textTertiary)
                .padding(.leading, Theme.Space.s16)
            Spacer()
        }
        .padding(.vertical, Theme.Space.s8)
        .background(Theme.Color.surfaceSidebarList)
    }
}

private struct ShortcutEditableRow: View {
    let label: String
    @Binding var hotkey: String?

    var body: some View {
        HStack {
            Text(label)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Color.textInverse)
                .padding(.leading, Theme.Space.s16)
            Spacer()
            ShortcutRecorderView(hotkey: $hotkey)
                .padding(.trailing, Theme.Space.s16)
        }
        .frame(height: 40)
    }
}

private struct ShortcutStaticRow: View {
    let label: String
    let shortcut: String

    var body: some View {
        HStack {
            Text(label)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Color.textInverse)
                .padding(.leading, Theme.Space.s16)
            Spacer()
            Text(shortcut)
                .font(Theme.Font.monoBody)
                .foregroundStyle(Theme.Color.textTertiary)
                .padding(.trailing, Theme.Space.s16)
        }
        .frame(height: 36)
    }
}

private struct ShortcutDividerRow: View {
    var body: some View {
        Rectangle()
            .fill(Theme.Color.surfaceRaised)
            .frame(height: Theme.Stroke.hairline)
            .padding(.horizontal, Theme.Space.s16)
    }
}

// MARK: - Tag hotkey row (bindable)

private struct TagHotkeyRow: View {
    let tag: CustomTag
    @ObservedObject var tagStore: TagStore

    var body: some View {
        HStack {
            HStack(spacing: Theme.Space.s8) {
                Circle()
                    .fill(tag.color)
                    .frame(width: 8, height: 8)
                Text(tag.name)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Color.textInverse)
            }
            .padding(.leading, Theme.Space.s16)
            Spacer()
            ShortcutRecorderView(
                hotkey: Binding(
                    get: { tag.hotkey },
                    set: { newValue in
                        var updated = tag
                        updated.hotkey = newValue
                        tagStore.updateTag(updated)
                    }
                ),
                validationMessage: { proposed in
                    if let reason = TagHotkeyRules.reservedReason(for: proposed) {
                        return "Used by \(reason)"
                    }
                    if let other = tagStore.tags.first(where: { $0.id != tag.id && $0.hotkey == proposed }) {
                        return "Used by \(other.name)"
                    }
                    return nil
                }
            )
            .padding(.trailing, Theme.Space.s16)
        }
        .frame(height: 40)
    }
}

// MARK: - Grouping helper

extension ShortcutsDetailContent {
    struct CategoryGroup {
        let categoryID: UUID?
        let categoryName: String
        let tags: [CustomTag]
    }

    static func groupedByCategory(
        _ tags: [CustomTag],
        categoryName: (UUID) -> String
    ) -> [CategoryGroup] {
        let buckets = Dictionary(grouping: tags, by: \.categoryID)
        return buckets
            .map { (id, tags) in
                CategoryGroup(
                    categoryID: id,
                    categoryName: categoryName(id),
                    tags: tags.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                )
            }
            .sorted { lhs, rhs in
                if lhs.categoryName == "Uncategorized" { return false }
                if rhs.categoryName == "Uncategorized" { return true }
                return lhs.categoryName.localizedCaseInsensitiveCompare(rhs.categoryName) == .orderedAscending
            }
    }
}
