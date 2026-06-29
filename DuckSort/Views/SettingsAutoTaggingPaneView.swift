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
    @State private var showSampleInspectorSheet = false
    @State private var sampleFileMetadata: (filename: String, snapshot: MetadataSnapshot)? = nil
    @State private var editingRule: AutoTagRule? = nil
    @State private var hoveredRuleID: UUID? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: Theme.Space.s4) {
                    Text("Auto Tagging & AI Vision")
                        .font(Theme.Font.title)
                        .foregroundStyle(Theme.Color.textPrimary)

                    Text("Configure on-device AI Vision machine learning and background EXIF rules.")
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
                    preferences.save()
                } label: {
                    Label("Reset Defaults", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    selectSampleFileAndInspect()
                } label: {
                    Label("Inspect Photo / XMP...", systemImage: "doc.badge.gearshape")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Select a photo or XMP sidecar file to inspect its metadata and generate auto-tag rules")

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
                    if let index = preferences.autoTaggingRules.firstIndex(where: { $0.id == newRule.id }) {
                        preferences.autoTaggingRules[index] = newRule
                    } else {
                        preferences.autoTaggingRules.append(newRule)
                    }
                    preferences.save()
                    editingRule = nil
                },
                onCancel: { editingRule = nil }
            )
            .frame(width: 500, height: 650)
        }
        .sheet(isPresented: $showSampleInspectorSheet) {
            if let sample = sampleFileMetadata {
                SampleMetadataInspectorSheet(
                    filename: sample.filename,
                    snapshot: sample.snapshot,
                    isPresented: $showSampleInspectorSheet,
                    onCreateRule: { newRule in
                        showSampleInspectorSheet = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            editingRule = newRule
                            showAddRuleSheet = true
                        }
                    }
                )
            }
        }
    }

    private func selectSampleFileAndInspect() {
        let panel = NSOpenPanel()
        panel.title = "Select a Photo or XMP File"
        panel.prompt = "Inspect Metadata"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            let snapshot = MetadataReader().metadata(for: url)
            sampleFileMetadata = (url.lastPathComponent, snapshot)
            showSampleInspectorSheet = true
        }
    }

    // MARK: - Views

    private var infoCard: some View {
        HStack(alignment: .top, spacing: Theme.Space.s12) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 16))
                .foregroundStyle(Theme.Color.accent)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: Theme.Space.s6) {
                Text("How Auto-Tagging Evaluates Your Library")
                    .font(Theme.Font.bodyBold)
                    .foregroundStyle(Theme.Color.textPrimary)

                HStack(spacing: Theme.Space.s12) {
                    guideStep(icon: "camera.fill", title: "1. Read EXIF", desc: "Reads camera, lens, ISO, focal length, aperture & flash.")
                    guideStep(icon: "slider.horizontal.3", title: "2. Evaluate Rules", desc: "Matches active rules against photo metadata.")
                    guideStep(icon: "tag.fill", title: "3. Suggest Tags", desc: "Presents one-click tag pills in the Large Viewer.")
                }
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

    private func guideStep(icon: String, title: String, desc: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.Color.accent)
                Text(title)
                    .font(Theme.Font.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(Theme.Color.textPrimary)
            }
            Text(desc)
                .font(.system(size: 10))
                .foregroundStyle(Theme.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                            preferences.save()
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
                HStack(spacing: Theme.Space.s6) {
                    Text(rule.name)
                        .font(Theme.Font.bodyBold)
                        .foregroundStyle(rule.enabled ? Theme.Color.textPrimary : Theme.Color.textSecondary)

                    confidenceBadge(rule.confidence)
                }

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
                            preferences.save()
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

    private func confidenceBadge(_ confidence: Confidence) -> some View {
        let (title, color) = confidenceDetails(confidence)
        return Text(title)
            .font(.system(size: 9, weight: .bold))
            .tracking(0.5)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }

    private func confidenceDetails(_ confidence: Confidence) -> (String, Color) {
        switch confidence {
        case .high:   return ("HIGH CONFIDENCE", Theme.Color.success)
        case .medium: return ("MED CONFIDENCE", Theme.Color.warning)
        case .low:    return ("LOW CONFIDENCE", Theme.Color.textSecondary)
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
            return "magnifyingglass.circle"
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

        let initialName: String
        let initialEnabled: Bool
        let initialConfidence: Confidence
        let initialConditionType: ConditionType
        let initialConditionValue: String
        let initialTagNames: String
        let initialCategory: String

        if let rule {
            initialName = rule.name
            initialEnabled = rule.enabled
            initialConfidence = rule.confidence
            initialTagNames = rule.suggestedTags.map(\.name).joined(separator: ", ")
            initialCategory = rule.suggestedTags.first?.category ?? ""

            switch rule.condition {
            case .cameraBrand:
                initialConditionType = .cameraBrand
                initialConditionValue = ""
            case .cameraBrandValue(let v):
                initialConditionType = .cameraBrand
                initialConditionValue = v
            case .focalLength35mmLess:
                initialConditionType = .focalLength35mmLess
                initialConditionValue = "35"
            case .focalLength35mmValue(let v):
                initialConditionType = .focalLength35mmLess
                initialConditionValue = String(Int(v))
            case .focalLength35mmMore:
                initialConditionType = .focalLength35mmMore
                initialConditionValue = "200"
            case .isoLess:
                initialConditionType = .isoLess
                initialConditionValue = "200"
            case .isoValue(let v):
                initialConditionType = .isoLess
                initialConditionValue = String(v)
            case .isoMore:
                initialConditionType = .isoMore
                initialConditionValue = "3200"
            case .apertureLess:
                initialConditionType = .apertureLess
                initialConditionValue = "2.8"
            case .apertureValue(let v):
                initialConditionType = .apertureLess
                initialConditionValue = String(format: "%.1f", v)
            case .apertureMore:
                initialConditionType = .apertureMore
                initialConditionValue = "8.0"
            case .flashFired:
                initialConditionType = .flashFired
                initialConditionValue = ""
            case .flashNotFired:
                initialConditionType = .flashNotFired
                initialConditionValue = ""
            case .aspectRatio:
                initialConditionType = .aspectRatio
                initialConditionValue = "1.5"
            case .aspectRatioValue(let v):
                initialConditionType = .aspectRatio
                initialConditionValue = String(format: "%.2f", v)
            case .imageStabilization:
                initialConditionType = .imageStabilization
                initialConditionValue = ""
            case .lensType:
                initialConditionType = .lensTypeContains
                initialConditionValue = ""
            case .lensTypeValue(let v):
                initialConditionType = .lensTypeContains
                initialConditionValue = v
            case .lensTypeNot:
                initialConditionType = .lensTypeNotContains
                initialConditionValue = ""
            case .lensTypeNotValue(let v):
                initialConditionType = .lensTypeNotContains
                initialConditionValue = v
            }
        } else {
            initialName = ""
            initialEnabled = true
            initialConfidence = .medium
            initialConditionType = .cameraBrand
            initialConditionValue = ""
            initialTagNames = ""
            initialCategory = ""
        }

        _name = State(initialValue: initialName)
        _enabled = State(initialValue: initialEnabled)
        _confidence = State(initialValue: initialConfidence)
        _selectedCondition = State(initialValue: initialConditionType)
        _conditionValue = State(initialValue: initialConditionValue)
        _suggestedTagNames = State(initialValue: initialTagNames)
        _suggestedCategory = State(initialValue: initialCategory)
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

                    // Target EXIF / XMP Query Inspector Box (shows exact underlying configuration)
                    VStack(alignment: .leading, spacing: Theme.Space.s4) {
                        Text("Target EXIF / XMP Query Configuration")
                            .font(Theme.Font.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(Theme.Color.textSecondary)

                        HStack(spacing: Theme.Space.s6) {
                            Image(systemName: "terminal.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.Color.accent)
                            Text(currentConstructedCondition.targetFieldDescription)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Theme.Color.textPrimary)
                        }
                        .padding(Theme.Space.s8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.Color.surfaceBase, in: RoundedRectangle(cornerRadius: Theme.Radius.s))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.s)
                                .stroke(Theme.Color.surfaceDivider, lineWidth: Theme.Stroke.hairline)
                        )
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

    private var currentConstructedCondition: Condition {
        switch selectedCondition {
        case .cameraBrand:
            return Condition.cameraBrandValue(conditionValue)
        case .focalLength35mmLess:
            let val = Double(conditionValue) ?? 35.0
            return Condition.focalLength35mmValue(val)
        case .focalLength35mmMore:
            let val = Double(conditionValue) ?? 200.0
            return Condition.focalLength35mmValue(val)
        case .isoLess:
            let val = Int(conditionValue) ?? 200
            return Condition.isoValue(val)
        case .isoMore:
            let val = Int(conditionValue) ?? 3200
            return Condition.isoValue(val)
        case .apertureLess:
            let val = Double(conditionValue) ?? 2.8
            return Condition.apertureValue(val)
        case .apertureMore:
            let val = Double(conditionValue) ?? 8.0
            return Condition.apertureValue(val)
        case .flashFired:
            return Condition.flashFired
        case .flashNotFired:
            return Condition.flashNotFired
        case .aspectRatio:
            let val = Double(conditionValue) ?? 1.5
            return Condition.aspectRatioValue(val)
        case .lensTypeContains:
            return Condition.lensTypeValue(conditionValue)
        case .lensTypeNotContains:
            return Condition.lensTypeNotValue(conditionValue)
        case .imageStabilization:
            return Condition.imageStabilization
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

// MARK: - Sample Metadata Inspector Sheet

private struct SampleMetadataInspectorSheet: View {
    let filename: String
    let snapshot: MetadataSnapshot
    @Binding var isPresented: Bool
    let onCreateRule: (AutoTagRule) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Inspect Metadata: \(filename)")
                        .font(Theme.Font.title)
                        .foregroundStyle(Theme.Color.textPrimary)
                    Text("Found metadata fields in this file. Click '+ Create Rule' next to any field to generate a new auto-tagging rule.")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Color.textSecondary)
                }
                Spacer()
                Button("Done") { isPresented = false }
                    .buttonStyle(.borderedProminent)
            }

            Divider().overlay(Theme.Color.surfaceDivider)

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.s10) {
                    if let camera = snapshot.cameraModel, !camera.isEmpty {
                        metadataRow(
                            label: "Camera Model",
                            value: camera,
                            systemImage: "camera",
                            rule: AutoTagRule(
                                id: UUID(),
                                name: "Camera: \(camera)",
                                condition: .cameraBrandValue(camera),
                                suggestedTags: [.init(name: camera.components(separatedBy: " ").first ?? camera, category: nil)]
                            )
                        )
                    }

                    if let lens = snapshot.lensModel, !lens.isEmpty {
                        metadataRow(
                            label: "Lens Model",
                            value: lens,
                            systemImage: "magnifyingglass.circle",
                            rule: AutoTagRule(
                                id: UUID(),
                                name: "Lens: \(lens)",
                                condition: .lensTypeValue(lens),
                                suggestedTags: [.init(name: "Lens Tag", category: nil)]
                            )
                        )
                    }

                    if let focal = snapshot.focalLengthIn35mm {
                        metadataRow(
                            label: "Focal Length (35mm eq.)",
                            value: "\(Int(focal))mm",
                            systemImage: "scope",
                            rule: AutoTagRule(
                                id: UUID(),
                                name: "Focal Length \(Int(focal))mm",
                                condition: .focalLength35mmValue(focal),
                                suggestedTags: [.init(name: focal < 35 ? "Wide Angle" : (focal > 100 ? "Telephoto" : "Standard Focal"), category: nil)]
                            )
                        )
                    }

                    if let iso = snapshot.iso {
                        metadataRow(
                            label: "ISO Speed",
                            value: "\(iso)",
                            systemImage: "sensor.fill",
                            rule: AutoTagRule(
                                id: UUID(),
                                name: "ISO \(iso)",
                                condition: .isoValue(iso),
                                suggestedTags: [.init(name: iso > 1600 ? "High ISO" : "Low ISO", category: nil)]
                            )
                        )
                    }

                    if let ap = snapshot.aperture {
                        metadataRow(
                            label: "Aperture",
                            value: "f/\(String(format: "%.1f", ap))",
                            systemImage: "camera.aperture",
                            rule: AutoTagRule(
                                id: UUID(),
                                name: "Aperture f/\(String(format: "%.1f", ap))",
                                condition: .apertureValue(ap),
                                suggestedTags: [.init(name: ap < 2.8 ? "Shallow DoF" : "Deep DoF", category: nil)]
                            )
                        )
                    }

                    if let flash = snapshot.flashFired {
                        metadataRow(
                            label: "Flash State",
                            value: flash ? "Fired" : "Did not fire",
                            systemImage: "bolt.fill",
                            rule: AutoTagRule(
                                id: UUID(),
                                name: flash ? "Flash Fired" : "Flash Off",
                                condition: flash ? .flashFired : .flashNotFired,
                                suggestedTags: [.init(name: flash ? "Flash" : "Natural Light", category: nil)]
                            )
                        )
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(Theme.Space.s20)
        .frame(width: 520, height: 460)
        .background(Theme.Color.surfaceBase)
    }

    private func metadataRow(label: String, value: String, systemImage: String, rule: AutoTagRule) -> some View {
        HStack(spacing: Theme.Space.s12) {
            Image(systemName: systemImage)
                .font(.system(size: 14))
                .foregroundStyle(Theme.Color.accent)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(Theme.Font.caption2)
                    .foregroundStyle(Theme.Color.textSecondary)
                Text(value)
                    .font(Theme.Font.bodyBold)
                    .foregroundStyle(Theme.Color.textPrimary)
            }

            Spacer()

            Button {
                onCreateRule(rule)
                isPresented = false
            } label: {
                Label("Create Rule", systemImage: "plus.circle")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(Theme.Space.s10)
        .background(Theme.Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.m))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.m)
                .stroke(Theme.Color.surfaceDivider, lineWidth: Theme.Stroke.hairline)
        )
    }
}
