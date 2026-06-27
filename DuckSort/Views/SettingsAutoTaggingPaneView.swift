//
//  SettingsAutoTaggingPaneView.swift
//  DuckSort
//
//  Settings tab for configuring auto-tagging rules. Overhauled with
//  premium macOS design system integration, rule condition icons, tag pills,
//  and inline deletion support.
//

import SwiftUI

struct SettingsAutoTaggingPaneView: View {
    @ObservedObject var preferences: UserPreferences
    @ObservedObject var tagStore: TagStore

    @State private var showAddRuleSheet = false
    @State private var editingRule: AutoTagRule? = nil
    @State private var hoveredRuleID: UUID? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: Theme.Space.s4) {
                    Text("Auto Tagging")
                        .font(Theme.Font.title)
                        .foregroundStyle(Theme.Color.textPrimary)

                    Text("Suggest tags based on EXIF camera metadata when focusing a photo.")
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.Color.textSecondary)
                }

                Spacer()

                Toggle("", isOn: $preferences.autoTaggingEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
            }
            .padding(.bottom, Theme.Space.s4)

            Divider()
                .background(Theme.Color.separator)

            // How-to guide banner
            infoCard

            // Rule list
            if preferences.autoTaggingRules.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Active Rules")
                            .font(Theme.Font.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.Color.textSecondary)
                        Spacer()
                    }
                    .padding(.bottom, Theme.Space.s8)

                    ScrollView {
                        VStack(spacing: Theme.Space.s8) {
                            ForEach(preferences.autoTaggingRules, id: \.id) { rule in
                                ruleRow(rule)
                            }
                        }
                        .padding(.vertical, Theme.Space.s2)
                    }
                }
            }

            // Bottom Actions
            HStack {
                Button {
                    preferences.autoTaggingRules = AutoTagRule.defaultRules
                } label: {
                    Label("Reset Defaults", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                Button {
                    editingRule = nil
                    showAddRuleSheet = true
                } label: {
                    Label("Add Rule", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.top, Theme.Space.s12)
        }
        .padding(Theme.Space.s20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.Color.surfaceBase)
        .sheet(isPresented: $showAddRuleSheet) {
            RuleEditorSheet(
                rule: editingRule,
                categories: tagStore.categories.map(\.name),
                onSave: { newRule in
                    if let existing = editingRule {
                        // Replace existing rule
                        if let index = preferences.autoTaggingRules.firstIndex(where: { $0.id == existing.id }) {
                            preferences.autoTaggingRules[index] = newRule
                        }
                    } else {
                        // Add new rule
                        preferences.autoTaggingRules.append(newRule)
                    }
                    editingRule = nil
                },
                onCancel: { editingRule = nil }
            )
            .frame(width: 480, height: 520)
        }
    }

    // MARK: - Views

    private var infoCard: some View {
        HStack(alignment: .top, spacing: Theme.Space.s10) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(Theme.Color.accent)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text("How to configure rules:")
                    .font(Theme.Font.bodyBold)
                    .foregroundStyle(Theme.Color.textPrimary)

                Text("Click the 'Add Rule' button below to create a new mapping. Choose a metadata condition (such as camera brand, focal length, ISO, aperture, or flash state), enter a matching threshold value, and specify the tags to suggest. When you view a photo in the large image viewer, matching tags will appear at the bottom of the sidebar for quick culling.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .lineLimit(4)
            }
        }
        .padding(Theme.Space.s12)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.m)
                .fill(Theme.Color.accent.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.m)
                .stroke(Theme.Color.accent.opacity(0.18), lineWidth: 1)
        )
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Space.s12) {
            Image(systemName: "tag.slash")
                .font(.system(size: 32))
                .foregroundStyle(Theme.Color.textTertiary)

            Text("No Auto-Tagging Rules")
                .font(Theme.Font.headline)
                .foregroundStyle(Theme.Color.textSecondary)

            Text("Create a rule to automatically suggest keyword tags when viewing photos.")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, Theme.Space.s24)
    }

    private func ruleRow(_ rule: AutoTagRule) -> some View {
        let isHovered = hoveredRuleID == rule.id

        return HStack(spacing: Theme.Space.s12) {
            // Enabled state switch
            Toggle("", isOn: Binding(
                get: { rule.enabled },
                set: { newValue in
                    if let index = preferences.autoTaggingRules.firstIndex(where: { $0.id == rule.id }) {
                        withAnimation(.smooth(duration: 0.15)) {
                            preferences.autoTaggingRules[index].enabled = newValue
                        }
                    }
                }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.small)

            // Icon for metadata type
            let color = iconColorForCondition(rule.condition)
            Image(systemName: iconForCondition(rule.condition))
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 24, height: 24)
                .background(color.opacity(0.12), in: Circle())

            // Rule Details
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.name)
                    .font(Theme.Font.bodyBold)
                    .foregroundStyle(rule.enabled ? Theme.Color.textPrimary : Theme.Color.textSecondary)

                Text(rule.condition.description)
                    .font(Theme.Font.footnote)
                    .foregroundStyle(Theme.Color.textSecondary)
            }

            Spacer()

            // Suggested tags (pills)
            HStack(spacing: Theme.Space.s4) {
                ForEach(rule.suggestedTags, id: \.name) { tag in
                    Text(tag.name)
                        .font(Theme.Font.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.Color.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(Theme.Color.accent.opacity(0.08))
                        )
                        .overlay(
                            Capsule().stroke(Theme.Color.accent.opacity(0.2), lineWidth: 1)
                        )
                }
            }
            .opacity(rule.enabled ? 1.0 : 0.5)

            // Inline actions on hover
            HStack(spacing: Theme.Space.s8) {
                if isHovered {
                    Button {
                        editingRule = rule
                        showAddRuleSheet = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Color.textSecondary)
                            .frame(width: 20, height: 20)
                            .background(Theme.Color.overlaySoft, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Edit Rule")

                    Button {
                        withAnimation(.smooth(duration: 0.15)) {
                            preferences.autoTaggingRules.removeAll(where: { $0.id == rule.id })
                        }
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Color.danger)
                            .frame(width: 20, height: 20)
                            .background(Theme.Color.danger.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Delete Rule")
                } else {
                    Spacer().frame(width: 48)
                }
            }
            .frame(width: 48)
        }
        .padding(.horizontal, Theme.Space.s12)
        .padding(.vertical, Theme.Space.s8)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.l)
                .fill(rule.enabled ? Theme.Color.cellBackground : Theme.Color.cellBackground.opacity(0.4))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.l)
                .stroke(isHovered ? Theme.Color.accent.opacity(0.25) : Theme.Color.separator, lineWidth: Theme.Stroke.hairline)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                hoveredRuleID = hovering ? rule.id : nil
            }
        }
    }

    // MARK: - Condition Mapping Helpers

    private func iconForCondition(_ condition: Condition) -> String {
        switch condition {
        case .cameraBrand, .cameraBrandValue:
            return "camera"
        case .focalLength35mmLess, .focalLength35mmMore, .focalLength35mmValue:
            return "scope"
        case .isoLess, .isoMore, .isoValue:
            return "sensor.fill"
        case .apertureLess, .apertureMore, .apertureValue:
            return "camera.aperture"
        case .flashFired, .flashNotFired:
            return "bolt.fill"
        case .aspectRatio, .aspectRatioValue:
            return "aspectratio"
        case .lensType, .lensTypeValue, .lensTypeNot, .lensTypeNotValue:
            return "sparkles.square"
        case .imageStabilization:
            return "hand.wave"
        }
    }

    private func iconColorForCondition(_ condition: Condition) -> Color {
        switch condition {
        case .cameraBrand, .cameraBrandValue:
            return Color.blue
        case .focalLength35mmLess, .focalLength35mmMore, .focalLength35mmValue:
            return Color.teal
        case .isoLess, .isoMore, .isoValue:
            return Color.orange
        case .apertureLess, .apertureMore, .apertureValue:
            return Color.purple
        case .flashFired, .flashNotFired:
            return Color.yellow
        case .aspectRatio, .aspectRatioValue:
            return Color.pink
        case .lensType, .lensTypeValue, .lensTypeNot, .lensTypeNotValue:
            return Color.green
        case .imageStabilization:
            return Color.red
        }
    }
}

// MARK: - Rule Editor Sheet

private struct RuleEditorSheet: View {
    let rule: AutoTagRule?
    let categories: [String]

    let onSave: (AutoTagRule) -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss

    // Rule properties
    @State private var name: String = ""
    @State private var enabled: Bool = true
    @State private var confidence: Confidence = .medium
    @State private var selectedCondition: ConditionType = .cameraBrand
    @State private var conditionValue: String = ""
    @State private var suggestedTagNames: String = ""
    @State private var suggestedCategory: String = ""

    enum ConditionType: String, CaseIterable, Identifiable {
        case cameraBrand = "Camera Brand"
        case focalLength35mmLess = "Focal Length < (35mm eq.)"
        case focalLength35mmMore = "Focal Length > (35mm eq.)"
        case isoLess = "ISO <"
        case isoMore = "ISO >"
        case apertureLess = "Aperture <"
        case apertureMore = "Aperture >"
        case flashFired = "Flash Fired"
        case flashNotFired = "Flash Did Not Fire"
        case aspectRatio = "Aspect Ratio"
        case lensTypeContains = "Lens Contains"
        case lensTypeNotContains = "Lens Does Not Contain"
        case imageStabilization = "Image Stabilization"

        var id: String { rawValue }

        var needsValue: Bool {
            switch self {
            case .cameraBrand, .focalLength35mmLess, .focalLength35mmMore,
                 .isoLess, .isoMore, .apertureLess, .apertureMore,
                 .lensTypeContains, .lensTypeNotContains:
                return true
            case .flashFired, .flashNotFired, .aspectRatio, .imageStabilization:
                return false
            }
        }
    }

    init(
        rule: AutoTagRule?,
        categories: [String],
        onSave: @escaping (AutoTagRule) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.rule = rule
        self.categories = categories
        self.onSave = onSave
        self.onCancel = onCancel

        if let rule {
            name = rule.name
            enabled = rule.enabled
            confidence = rule.confidence
            suggestedTagNames = rule.suggestedTags.map(\.name).joined(separator: ", ")
            suggestedCategory = rule.suggestedTags.first?.category ?? ""

            // Map existing condition to a ConditionType.
            switch rule.condition {
            case .cameraBrand:
                selectedCondition = .cameraBrand
                conditionValue = ""
            case .cameraBrandValue(let v):
                selectedCondition = .cameraBrand
                conditionValue = v
            case .focalLength35mmLess:
                selectedCondition = .focalLength35mmLess
                conditionValue = "35"
            case .focalLength35mmValue(let v):
                selectedCondition = .focalLength35mmLess
                conditionValue = String(v)
            case .focalLength35mmMore:
                selectedCondition = .focalLength35mmMore
                conditionValue = "200"
            case .isoLess:
                selectedCondition = .isoLess
                conditionValue = "200"
            case .isoValue(let v):
                selectedCondition = .isoLess
                conditionValue = String(v)
            case .isoMore:
                selectedCondition = .isoMore
                conditionValue = "3200"
            case .apertureLess:
                selectedCondition = .apertureLess
                conditionValue = "2.8"
            case .apertureValue(let v):
                selectedCondition = .apertureLess
                conditionValue = String(format: "%.1f", v)
            case .apertureMore:
                selectedCondition = .apertureMore
                conditionValue = "8.0"
            case .flashFired:
                selectedCondition = .flashFired
            case .flashNotFired:
                selectedCondition = .flashNotFired
            case .aspectRatio:
                selectedCondition = .aspectRatio
            case .aspectRatioValue(let v):
                selectedCondition = .aspectRatio
                conditionValue = String(format: "%.2f", v)
            case .imageStabilization:
                selectedCondition = .imageStabilization
            case .lensType:
                selectedCondition = .lensTypeContains
                conditionValue = ""
            case .lensTypeValue(let v):
                selectedCondition = .lensTypeContains
                conditionValue = v
            case .lensTypeNot:
                selectedCondition = .lensTypeNotContains
                conditionValue = ""
            case .lensTypeNotValue(let v):
                selectedCondition = .lensTypeNotContains
                conditionValue = v
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(rule == nil ? "New Auto-Tagging Rule" : "Edit Auto-Tagging Rule")
                    .font(Theme.Font.title)
                    .fontWeight(.bold)
                    .foregroundStyle(Theme.Color.textPrimary)
                Spacer()
            }
            .padding(.horizontal, Theme.Space.s20)
            .padding(.top, Theme.Space.s20)
            .padding(.bottom, Theme.Space.s16)

            Divider()
                .background(Theme.Color.separator)

            // Form container
            Form {
                VStack(alignment: .leading, spacing: Theme.Space.s14) {
                    // Enable Toggle
                    Toggle("Rule Enabled", isOn: $enabled)
                        .toggleStyle(.switch)
                        .controlSize(.small)

                    // Rule Name
                    VStack(alignment: .leading, spacing: Theme.Space.s4) {
                        Text("Rule Name")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Color.textSecondary)
                        TextField("e.g. Fuji Cameras or Wide Focal", text: $name)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Confidence Level
                    VStack(alignment: .leading, spacing: Theme.Space.s4) {
                        Text("Confidence Level")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Color.textSecondary)
                        Picker("", selection: $confidence) {
                            Text("High").tag(Confidence.high)
                            Text("Medium").tag(Confidence.medium)
                            Text("Low").tag(Confidence.low)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                    }

                    // Condition selection
                    VStack(alignment: .leading, spacing: Theme.Space.s4) {
                        Text("When photo matches condition")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Color.textSecondary)
                        Picker("", selection: $selectedCondition) {
                            ForEach(ConditionType.allCases) { type in
                                Text(type.rawValue).tag(type)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                    }

                    // Condition threshold value
                    if selectedCondition.needsValue {
                        VStack(alignment: .leading, spacing: Theme.Space.s4) {
                            Text(selectedCondition == .cameraBrand || selectedCondition == .lensTypeContains || selectedCondition == .lensTypeNotContains
                                 ? "Match Value"
                                 : "Threshold Value")
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Color.textSecondary)
                            TextField(selectedCondition == .cameraBrand || selectedCondition == .lensTypeContains || selectedCondition == .lensTypeNotContains
                                      ? "e.g. Fujifilm"
                                      : "0.0", text: $conditionValue)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    // Suggested tags
                    VStack(alignment: .leading, spacing: Theme.Space.s4) {
                        Text("Suggested Tag Names")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Color.textSecondary)
                        TextField("e.g. Fuji, Fujifilm (comma-separated)", text: $suggestedTagNames)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Category
                    VStack(alignment: .leading, spacing: Theme.Space.s4) {
                        Text("Optional Category")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Color.textSecondary)

                        Picker("", selection: $suggestedCategory) {
                            Text("Create New Category").tag("")
                            ForEach(categories, id: \.self) { cat in
                                Text(cat).tag(cat)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, Theme.Space.s20)
                .padding(.vertical, Theme.Space.s16)
            }
            .scrollDisabled(true)

            Spacer()

            Divider()
                .background(Theme.Color.separator)

            // Buttons
            HStack(spacing: Theme.Space.s12) {
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                    onCancel()
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Button(rule == nil ? "Create Rule" : "Save Changes") {
                    saveRule()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                          suggestedTagNames.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, Theme.Space.s20)
            .padding(.vertical, Theme.Space.s16)
        }
        .background(Theme.Color.surfaceRaised)
        .onAppear {
            if !categories.isEmpty && suggestedCategory.isEmpty {
                suggestedCategory = categories.first ?? ""
            }
        }
    }

    private func saveRule() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTags = suggestedTagNames
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let trimmedCategory = suggestedCategory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : suggestedCategory.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty, !trimmedTags.isEmpty else { return }

        let suggestedTags = trimmedTags.map { SuggestedTag(name: $0, category: trimmedCategory) }

        let condition: Condition
        switch selectedCondition {
        case .cameraBrand:
            condition = Condition.cameraBrandValue(conditionValue)
        case .focalLength35mmLess:
            condition = Condition.focalLength35mmValue(Double(conditionValue) ?? 35.0)
        case .focalLength35mmMore:
            condition = Condition.focalLength35mmValue(Double(conditionValue) ?? 200.0)
        case .isoLess:
            condition = Condition.isoValue(Int(conditionValue) ?? 200)
        case .isoMore:
            condition = Condition.isoValue(Int(conditionValue) ?? 3200)
        case .apertureLess:
            condition = Condition.apertureValue(Double(conditionValue) ?? 2.8)
        case .apertureMore:
            condition = Condition.apertureValue(Double(conditionValue) ?? 8.0)
        case .flashFired:
            condition = Condition.flashFired
        case .flashNotFired:
            condition = Condition.flashNotFired
        case .aspectRatio:
            condition = Condition.aspectRatioValue(1.5)
        case .lensTypeContains:
            condition = Condition.lensTypeValue(conditionValue)
        case .lensTypeNotContains:
            condition = Condition.lensTypeNotValue(conditionValue)
        case .imageStabilization:
            condition = Condition.imageStabilization
        }

        let newRule = AutoTagRule(
            id: rule?.id ?? UUID(),
            name: trimmedName,
            enabled: enabled,
            condition: condition,
            suggestedTags: suggestedTags,
            confidence: confidence
        )

        onSave(newRule)
    }
}
