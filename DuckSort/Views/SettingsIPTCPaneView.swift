//
//  SettingsIPTCPaneView.swift
//  DuckSort
//
//  The "Copyright" tab of the unified Settings window. Lets the user enter
//  photographer name, copyright notice, and contact info once. When the
//  master toggle is on, these values are embedded into every XMP sidecar
//  the export pipeline writes.
//

import SwiftUI

struct SettingsIPTCPaneView: View {
    @ObservedObject var preferences: UserPreferences

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.s14) {
                masterToggle

                if preferences.embedIPTCInExports {
                    form
                } else {
                    emptyState
                }
            }
            .padding(.horizontal, Theme.Space.s20)
            .padding(.vertical, Theme.Space.s16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var masterToggle: some View {
        Toggle(isOn: $preferences.embedIPTCInExports) {
            HStack(spacing: Theme.Space.s8) {
                Image(systemName: "checkmark.seal")
                    .foregroundStyle(preferences.embedIPTCInExports
                                     ? Theme.Color.accent
                                     : Theme.Color.textSecondary)
                Text("Embed copyright in exports")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Color.textInverse)
            }
        }
        .toggleStyle(.switch)
        .onChange(of: preferences.embedIPTCInExports) { _, _ in
            preferences.save()
        }
    }

    private var emptyState: some View {
        HStack(spacing: Theme.Space.s8) {
            Image(systemName: "info.circle")
                .foregroundStyle(Theme.Color.textSecondary)
            Text("Toggle on to fill in your details.")
                .font(Theme.Font.subheadline)
                .foregroundStyle(Theme.Color.textSecondary)
        }
        .padding(.vertical, Theme.Space.s12)
        .padding(.horizontal, Theme.Space.s14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.m)
                .fill(Theme.Color.surfaceRaised.opacity(0.6))
        )
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s14) {
            sectionHeader("PHOTOGRAPHER")
            labeledField("Creator Name", text: $preferences.iptcCreatorName,
                          placeholder: "e.g. Jane Doe",
                          systemImage: "person.crop.square")

            sectionHeader("RIGHTS")
            labeledField("Copyright Notice", text: $preferences.iptcCopyrightNotice,
                          placeholder: "e.g. © 2026 Jane Doe. All rights reserved.",
                          systemImage: "c.circle")
            labeledField("Usage Terms", text: $preferences.iptcRightsUsageTerms,
                          placeholder: "e.g. Licensed for editorial use only.",
                          systemImage: "doc.text")

            sectionHeader("CONTACT")
            labeledField("Email", text: $preferences.iptcContactEmail,
                          placeholder: "jane@example.com",
                          systemImage: "envelope",
                          contentType: .emailAddress)
            labeledField("Phone", text: $preferences.iptcContactPhone,
                          placeholder: "+1 555 123 4567",
                          systemImage: "phone",
                          contentType: .telephoneNumber)
            labeledField("Website", text: $preferences.iptcContactWebsite,
                          placeholder: "https://janedoe.example",
                          systemImage: "globe",
                          contentType: .URL)
        }
        .onChange(of: preferences.iptcCreatorName) { _, _ in preferences.save() }
        .onChange(of: preferences.iptcCopyrightNotice) { _, _ in preferences.save() }
        .onChange(of: preferences.iptcContactEmail) { _, _ in preferences.save() }
        .onChange(of: preferences.iptcContactPhone) { _, _ in preferences.save() }
        .onChange(of: preferences.iptcContactWebsite) { _, _ in preferences.save() }
        .onChange(of: preferences.iptcRightsUsageTerms) { _, _ in preferences.save() }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(Theme.Font.caption2)
            .tracking(0.4)
            .foregroundStyle(Theme.Color.textSecondary)
            .padding(.top, Theme.Space.s6)
    }

    private func labeledField(
        _ label: String,
        text: Binding<String>,
        placeholder: String,
        systemImage: String,
        contentType: NSTextContentType? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s4) {
            Text(label)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Color.textInverse)
            HStack(spacing: Theme.Space.s8) {
                Image(systemName: systemImage)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .frame(width: 16)
                TextField(placeholder, text: text)
                    .textFieldStyle(.plain)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Color.textPrimary)
                    .textContentType(contentType)
            }
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
    }
}