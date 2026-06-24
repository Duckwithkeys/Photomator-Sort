//
//  SettingsRulesPaneView.swift
//  DuckSort
//
//  The "Rules" tab of the unified Settings window.
//

import SwiftUI

struct SettingsRulesPaneView: View {
    @ObservedObject var ruleStore: ExportRuleStore
    @ObservedObject var tagStore: TagStore

    var body: some View {
        SettingsSplitLayout {
            RulesSidebar(ruleStore: ruleStore, tagStore: tagStore)
        } detail: {
            RulesDetailPanel(ruleStore: ruleStore, tagStore: tagStore)
        }
    }
}

// MARK: - Left Sidebar

private struct RulesSidebar: View {
    @ObservedObject var ruleStore: ExportRuleStore
    @ObservedObject var tagStore: TagStore
    @State private var newRuleName: String = ""
    @FocusState private var isAddFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("MY RULE SETS")
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
                    ForEach(ruleStore.rules) { rule in
                        RuleSidebarRow(
                            rule: rule,
                            isSelected: ruleStore.selectedRuleID == rule.id,
                            tagStore: tagStore,
                            onSelect: { ruleStore.selectRule(id: rule.id) },
                            onDelete: { ruleStore.deleteRule(id: rule.id) }
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Rectangle()
                .fill(Theme.Color.surfaceDivider)
                .frame(height: Theme.Stroke.hairline)
                .padding(.horizontal, Theme.Space.s16)

            HStack(spacing: Theme.Space.s4) {
                TextField("New rule set", text: $newRuleName)
                    .textFieldStyle(.plain)
                    .font(Theme.Font.subheadline)
                    .foregroundStyle(Theme.Color.textInverse)
                    .focused($isAddFieldFocused)
                    .onSubmit(commitNewRule)

                Button(action: commitNewRule) {
                    Image(systemName: "plus")
                        .font(.system(size: Theme.Space.s12, weight: .medium))
                        .foregroundStyle(
                            newRuleName.trimmingCharacters(in: .whitespaces).isEmpty
                                ? Theme.Color.surfaceStroke
                                : Theme.Color.textSecondary
                        )
                }
                .buttonStyle(.plain)
                .disabled(newRuleName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, Theme.Space.s16)
            .padding(.vertical, Theme.Space.s10)
        }
    }

    private func commitNewRule() {
        let trimmed = newRuleName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        ruleStore.addRule(name: trimmed)
        newRuleName = ""
        isAddFieldFocused = false
    }
}

private struct RuleSidebarRow: View {
    let rule: ExportPathRule
    let isSelected: Bool
    let tagStore: TagStore
    let onSelect: () -> Void
    let onDelete: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: Theme.Space.s8) {
                Image(systemName: "circle")
                    .font(.system(size: Theme.Space.s10))
                    .foregroundStyle(isSelected ? Theme.Color.textInverse : Theme.Color.textSecondary)
                    .frame(width: 14)

                VStack(alignment: .leading, spacing: Theme.Space.s2) {
                    Text(rule.name)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Theme.Color.textInverse : Theme.Color.textPrimary)
                        .lineLimit(1)
                    if !rule.components.isEmpty {
                        Text(ExportPathRouter.describe(rule.components) {
                            tagStore.categoryName(id: $0)
                        })
                        .font(Theme.Font.badge)
                        .foregroundStyle(isSelected ? Theme.Color.textInverse.opacity(0.65) : Theme.Color.textTertiary)
                        .lineLimit(1)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, Theme.Space.s10)
            .padding(.vertical, Theme.Space.s6)
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
            Button("Delete", role: .destructive, action: onDelete)
        }
    }
}

// MARK: - Right Detail Panel

private struct RulesDetailPanel: View {
    @ObservedObject var ruleStore: ExportRuleStore
    @ObservedObject var tagStore: TagStore

    var body: some View {
        if let rule = ruleStore.selectedRule {
            RuleEditorDetail(rule: rule, ruleStore: ruleStore, tagStore: tagStore)
        } else {
            VStack {
                Spacer()
                Image(systemName: "arrow.triangle.branch")
                    .font(Theme.Font.iconLarge)
                    .foregroundStyle(Theme.Color.surfaceStroke)
                Text("Select a rule set to edit")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .padding(.top, Theme.Space.s6)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct RuleEditorDetail: View {
    let rule: ExportPathRule
    @ObservedObject var ruleStore: ExportRuleStore
    @ObservedObject var tagStore: TagStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Theme.Space.s12) {
                Text("Rule Name:")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .frame(width: 80, alignment: .trailing)

                TextField("Rule name", text: Binding(
                    get: { rule.name },
                    set: { newName in
                        var updated = rule
                        updated.name = newName
                        ruleStore.updateRule(updated)
                    }
                ))
                .textFieldStyle(.plain)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Color.textInverse)
                .padding(.horizontal, Theme.Space.s8)
                .padding(.vertical, Theme.Space.s4)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.m)
                        .fill(Theme.Color.overlaySoft)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.m)
                                .stroke(Theme.Color.surfaceStroke, lineWidth: Theme.Stroke.hairline)
                        )
                )

                Spacer()

                Text("\(rule.components.count) folder level\(rule.components.count == 1 ? "" : "s")")
                    .font(Theme.Font.footnote)
                    .foregroundStyle(Theme.Color.textTertiary)
            }
            .padding(.horizontal, Theme.Space.s16)
            .padding(.vertical, Theme.Space.s12)

            Rectangle()
                .fill(Theme.Color.surfaceRaised)
                .frame(height: Theme.Stroke.hairline)
                .padding(.horizontal, Theme.Space.s16)

            if rule.components.isEmpty {
                VStack {
                    Spacer()
                    Text("No folder levels yet. Add one below.")
                        .font(Theme.Font.subheadline)
                        .foregroundStyle(Theme.Color.textTertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(Array(rule.components.enumerated()), id: \.offset) { index, component in
                        RuleComponentRow(
                            component: component,
                            index: index,
                            rule: rule,
                            ruleStore: ruleStore,
                            tagStore: tagStore
                        )
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(Theme.Color.surfaceRaised)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    }
                    .onMove { from, to in
                        var updated = rule
                        updated.components.move(fromOffsets: from, toOffset: to)
                        ruleStore.updateRule(updated)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
            }

            Rectangle()
                .fill(Theme.Color.surfaceRaised)
                .frame(height: Theme.Stroke.hairline)
                .padding(.horizontal, Theme.Space.s16)

            HStack {
                Spacer()

                Menu {
                    Button("Camera Model") { addComponent(.cameraModel, to: rule) }
                    Button("Lens Model")   { addComponent(.lensModel, to: rule) }
                    Button("Capture Date") { addComponent(.captureDate, to: rule) }
                    Divider()
                    ForEach(tagStore.categories) { category in
                        Button(category.name) {
                            addComponent(.tagCategory(category.id), to: rule)
                        }
                    }
                    Divider()
                    Button("Custom Text…") { addComponent(.customText("Custom"), to: rule) }
                } label: {
                    HStack(spacing: Theme.Space.s4) {
                        Text("Add Folder Level")
                            .font(Theme.Font.subheadline)
                        Image(systemName: "plus")
                            .font(.system(size: Theme.Space.s10))
                    }
                    .foregroundStyle(Theme.Color.accent)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .padding(.horizontal, Theme.Space.s16)
            .padding(.vertical, Theme.Space.s10)
        }
    }

    private func addComponent(_ component: ExportPathComponent, to rule: ExportPathRule) {
        var updated = rule
        updated.components.append(component)
        ruleStore.updateRule(updated)
    }
}

private struct RuleComponentRow: View {
    let component: ExportPathComponent
    let index: Int
    let rule: ExportPathRule
    @ObservedObject var ruleStore: ExportRuleStore
    @ObservedObject var tagStore: TagStore
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Theme.Space.s10) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: Theme.Space.s10))
                .foregroundStyle(Theme.Color.textTertiary)

            HStack(spacing: Theme.Space.s8) {
                Image(systemName: component.systemImage)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .frame(width: 18)

                componentContent
            }

            Spacer()

            if isHovered {
                Button(action: removeComponent) {
                    Image(systemName: "minus.circle")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.Color.danger)
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .padding(.horizontal, Theme.Space.s16)
        .padding(.vertical, Theme.Space.s8)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovered = hovering }
        }
    }

    @ViewBuilder
    private var componentContent: some View {
        switch component {
        case .cameraModel, .lensModel, .captureDate:
            Text(component.displayName)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Color.textInverse)

        case .tagCategory(let id):
            Picker("", selection: Binding(
                get: {
                    tagStore.categories.contains(where: { $0.id == id })
                        ? id : (tagStore.categories.first?.id ?? id)
                },
                set: { newID in
                    var updated = rule
                    updated.components[index] = .tagCategory(newID)
                    ruleStore.updateRule(updated)
                }
            )) {
                ForEach(tagStore.categories) { cat in
                    Text(cat.name).tag(cat.id)
                }
            }
            .labelsHidden()
            .font(Theme.Font.body)
            .frame(maxWidth: 160, alignment: .leading)

        case .customText(let text):
            TextField("Custom text", text: Binding(
                get: { text },
                set: { newText in
                    var updated = rule
                    updated.components[index] = .customText(newText)
                    ruleStore.updateRule(updated)
                }
            ))
            .textFieldStyle(.plain)
            .font(Theme.Font.body)
            .foregroundStyle(Theme.Color.textInverse)
            .padding(.horizontal, Theme.Space.s6)
            .padding(.vertical, Theme.Space.s4)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.s)
                    .fill(Theme.Color.overlaySoft)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.s)
                            .stroke(Theme.Color.surfaceStroke, lineWidth: Theme.Stroke.hairline)
                    )
            )
            .frame(maxWidth: 160)
        }
    }

    private func removeComponent() {
        var updated = rule
        updated.components.remove(at: index)
        ruleStore.updateRule(updated)
    }
}
