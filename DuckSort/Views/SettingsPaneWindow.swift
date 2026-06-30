//
//  SettingsPaneWindow.swift
//  DuckSort
//
//  Unified Safari-style preferences window. Hosts Rules, Tags, and Shortcuts
//  panes behind a segmented top toolbar. Resizable.
//

import SwiftUI
import AppKit

// MARK: - Tab Enum

enum SettingsTab: String, CaseIterable {
    case rules      = "Rules"
    case tags       = "Tags"
    case xmpTags    = "XMP Tags"
    case copyright  = "Copyright"
    case shortcuts  = "Shortcuts"
    case autoTagging = "Mode Switching"

    var systemImage: String {
        switch self {
        case .rules:      return "folder.badge.gearshape"
        case .tags:       return "tag"
        case .xmpTags:    return "doc.badge.plus"
        case .copyright:  return "c.circle"
        case .shortcuts:  return "keyboard.badge.ellipsis"
        case .autoTagging: return "slider.horizontal.3"
        }
    }
}

// MARK: - Root Settings View

struct SettingsPaneView: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel
    var initialTab: SettingsTab = .rules
    var onClose: () -> Void = {}

    @State private var selectedTab: SettingsTab = .rules

    var body: some View {
        VStack(spacing: 0) {
            SettingsToolbar(selectedTab: $selectedTab)

            Rectangle()
                .fill(Theme.Color.surfaceDivider)
                .frame(height: Theme.Stroke.hairline)

            Group {
                switch selectedTab {
                case .rules:
                    SettingsRulesPaneView(
                        ruleStore: viewModel.ruleStore,
                        tagStore: viewModel.tagStore
                    )
                case .tags:
                    SettingsTagsPaneView(
                        viewModel: viewModel,
                        tagStore: viewModel.tagStore
                    )
                case .xmpTags:
                    SettingsXMPTagsPane(
                        viewModel: viewModel,
                        tagStore: viewModel.tagStore
                    )
                case .copyright:
                    SettingsIPTCPaneView(preferences: UserPreferences.shared)
                case .shortcuts:
                    SettingsShortcutsPaneView(viewModel: viewModel)
                case .autoTagging:
                    SettingsAutoTaggingPaneView(
                        preferences: UserPreferences.shared,
                        tagStore: viewModel.tagStore
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if selectedTab == .tags {
                Rectangle()
                    .fill(Theme.Color.surfaceDivider)
                    .frame(height: Theme.Stroke.hairline)
                SettingsFooter(tagStore: viewModel.tagStore)
            }
        }
        .frame(minWidth: 820, idealWidth: 960, minHeight: 560, idealHeight: 720)
        .background(Theme.Color.surfaceBase)
        .onAppear { selectedTab = initialTab }
    }
}

// MARK: - Toolbar

private struct SettingsToolbar: View {
    @Binding var selectedTab: SettingsTab

    var body: some View {
        HStack(spacing: 0) {
            Spacer()
            ForEach(SettingsTab.allCases, id: \.self) { tab in
                SettingsTabButton(tab: tab, isSelected: selectedTab == tab) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedTab = tab
                    }
                }
            }
            Spacer()
        }
        .padding(.top, Theme.Space.s6)
        .padding(.bottom, Theme.Space.s10)
        .frame(maxWidth: .infinity)
        .background(Theme.Color.surfaceBase)
    }
}

private struct SettingsTabButton: View {
    let tab: SettingsTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Theme.Space.s4) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 22, weight: .light))
                    .frame(width: 24, height: 24)
                Text(tab.rawValue)
                    .font(Theme.Font.subheadline)
            }
            .foregroundStyle(isSelected ? Theme.Color.textInverse : Theme.Color.textTertiary)
            .padding(.horizontal, Theme.Space.s20)
            .padding(.vertical, Theme.Space.s4)
            .background(
                isSelected
                    ? RoundedRectangle(cornerRadius: Theme.Radius.l).fill(Theme.Color.overlaySoft)
                    : RoundedRectangle(cornerRadius: Theme.Radius.l).fill(Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.l))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.18), value: isSelected)
    }
}

// MARK: - Footer

private struct SettingsFooter: View {
    @ObservedObject var tagStore: TagStore
    @State private var showContactConfirm = false
    @State private var pendingContactCount = 0

    var body: some View {
        Button(action: { showContactConfirm = true }) {
            Text("Import Contacts…")
                .font(Theme.Font.body)
        }
        .buttonStyle(.bordered)
        .padding(.horizontal, Theme.Space.s16)
        .padding(.vertical, Theme.Space.s10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Color.surfaceBase)
        .confirmationDialog(
            "Import \(pendingContactCount) contacts as tags?",
            isPresented: $showContactConfirm,
            titleVisibility: .visible
        ) {
            Button("Import") { performContactImport() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("New tags will be added under the People category. Existing tags with the same name are kept.")
        }
    }

    private func showContactPicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.vCard]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "Import Contacts as Tags"
        panel.prompt = "Inspect"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            pendingContactCount = parseVCardNames(content).count
            guard pendingContactCount > 0 else { return }
            showContactConfirm = true
        } catch {
            print("Failed to read vCard: \(error)")
        }
    }

    private func performContactImport() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.vCard]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "Import Contacts as Tags"
        panel.prompt = "Import"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let names = parseVCardNames(content)
            guard !names.isEmpty else { return }

            let categoryName = "People"
            let category: TagCategory
            if let existing = tagStore.categories.first(where: {
                $0.name.lowercased() == categoryName.lowercased()
            }) {
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
        } catch {
            print("Failed to import contacts: \(error)")
        }
    }

    private func parseVCardNames(_ content: String) -> [String] {
        var names: [String] = []
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.uppercased().hasPrefix("FN:") {
                let name = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { names.append(name) }
            } else if trimmed.uppercased().hasPrefix("FN;") {
                let parts = trimmed.split(separator: ":", maxSplits: 1)
                if parts.count == 2 {
                    let name = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty { names.append(name) }
                }
            }
        }
        return Array(Set(names)).sorted()
    }
}

// MARK: - Button Styles
//
// Replaced by SwiftUI's built-in `.bordered` and `.borderedProminent` styles
// wherever the previous custom styles were used. If a one-off capsule button
// is needed elsewhere, prefer `.buttonStyle(.borderedProminent)` and let
// SwiftUI handle keyboard focus + accent color.

// MARK: - Shared Settings Layout: Sidebar + Right Panel

struct SettingsSplitLayout<Sidebar: View, Detail: View>: View {
    @ViewBuilder var sidebar: () -> Sidebar
    @ViewBuilder var detail: () -> Detail

    var body: some View {
        HStack(spacing: 0) {
            sidebar()
                .frame(width: 200)
                .background(Theme.Color.surfaceSidebar)

            Rectangle()
                .fill(Theme.Color.surfaceDivider)
                .frame(width: Theme.Stroke.hairline)

            detail()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.Color.surfaceBase)
        }
    }
}
