//
//  ExportRuleEditorView.swift
//  PhotomatorSort
//
//  Sheet for creating, renaming, and editing the ordered list of
//  ExportPathComponents that make up an export routing rule.
//

import SwiftUI

struct ExportRuleEditorView: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel
    @ObservedObject var ruleStore: ExportRuleStore
    @ObservedObject var tagStore: TagStore
    @Environment(\.dismiss) private var dismiss
    
    @State private var newRuleName: String = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Export Routing Rules")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Done") {
                    dismiss()
                    NSApp.keyWindow?.close()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            HSplitView {
                ruleList
                    .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)

                if let rule = ruleStore.selectedRule {
                    ruleEditor(rule)
                } else {
                    VStack {
                        Spacer()
                        Text("Select a rule to edit, or add a new one.")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(minWidth: 460)
                }
            }
        }
        .frame(minWidth: 820, minHeight: 540)
    }

    private var ruleList: some View {
        VStack(alignment: .leading, spacing: 0) {
            List(selection: Binding(
                get: { ruleStore.selectedRuleID },
                set: { id in if let id { ruleStore.selectRule(id: id) } }
            )) {
                ForEach(ruleStore.rules) { rule in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rule.name)
                            .font(.body.weight(.medium))
                        Text(ExportPathRouter.describe(rule.components) {
                            tagStore.categoryName(id: $0)
                        })
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }
                    .tag(rule.id as UUID?)
                    .contextMenu {
                        Button("Delete", role: .destructive) {
                            ruleStore.deleteRule(id: rule.id)
                        }
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()

            HStack {
                TextField("New rule", text: $newRuleName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(commitNewRule)
                Button(action: commitNewRule) {
                    Image(systemName: "plus")
                }
                .disabled(newRuleName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(10)
        }
    }

    private func commitNewRule() {
        let trimmed = newRuleName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        ruleStore.addRule(name: trimmed)
        newRuleName = ""
    }

    @ViewBuilder
    private func ruleEditor(_ rule: ExportPathRule) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                TextField("Rule name", text: Binding(
                    get: { rule.name },
                    set: { newName in
                        var updated = rule
                        updated.name = newName
                        ruleStore.updateRule(updated)
                    }
                ))
                .textFieldStyle(.roundedBorder)

                Spacer()

                Text("\(rule.components.count) folder level(s)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()

            Divider()

            List {
                ForEach(Array(rule.components.enumerated()), id: \.offset) { index, component in
                    componentRow(component, index: index, rule: rule)
                }
                .onMove { from, to in
                    var updated = rule
                    updated.components.move(fromOffsets: from, toOffset: to)
                    ruleStore.updateRule(updated)
                }
            }
            .frame(minHeight: 220)

            Divider()

            HStack(spacing: 8) {
                Menu {
                    Button("Camera Model") { addComponent(.cameraModel, to: rule) }
                    Button("Lens Model") { addComponent(.lensModel, to: rule) }
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
                    Label("Add Folder Level", systemImage: "plus")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 200)

                Spacer()
            }
            .padding()
        }
    }

    @ViewBuilder
    private func componentRow(_ component: ExportPathComponent, index: Int, rule: ExportPathRule) -> some View {
        HStack {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
            Image(systemName: component.systemImage)
                .frame(width: 22)
            switch component {
            case .cameraModel, .lensModel, .captureDate:
                Text(component.displayName)
            case .tagCategory(let id):
                Picker("", selection: Binding(
                    get: {
                        if tagStore.categories.contains(where: { $0.id == id }) {
                            return id
                        } else {
                            return tagStore.categories.first?.id ?? id
                        }
                    },
                    set: { newID in
                        var updated = rule
                        updated.components[index] = .tagCategory(newID)
                        ruleStore.updateRule(updated)
                    }
                )) {
                    ForEach(tagStore.categories) { category in
                        Text(category.name).tag(category.id)
                    }
                }
                .labelsHidden()
                .frame(width: 200)
            case .customText(let text):
                TextField("Custom text", text: Binding(
                    get: { text },
                    set: { newText in
                        var updated = rule
                        updated.components[index] = .customText(newText)
                        ruleStore.updateRule(updated)
                    }
                ))
                .textFieldStyle(.roundedBorder)
            }

            Spacer()

            Button {
                var updated = rule
                updated.components.remove(at: index)
                ruleStore.updateRule(updated)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }

    private func addComponent(_ component: ExportPathComponent, to rule: ExportPathRule) {
        var updated = rule
        updated.components.append(component)
        ruleStore.updateRule(updated)
    }
}
