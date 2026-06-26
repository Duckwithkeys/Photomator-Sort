//
//  OnboardingFlow.swift
//  DuckSort
//
//  First-launch walkthrough that walks new users through the things they
//  need to set up before DuckSort is useful: pick a shoot folder, pick a
//  tag pack (or import contacts), set up a destination, and confirm. Re-
//  runnable from the Help menu at any time.
//
//  Every step calls out where in the app the user can find that setting
//  later (e.g. "Settings → Tags", "Settings → Rules"), so the wizard also
//  serves as a brief tour.
//

import SwiftUI
import AppKit

struct OnboardingFlow: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel
    @ObservedObject var preferences = UserPreferences.shared

    /// Called when the user finishes or skips so the parent can stop
    /// presenting the overlay.
    let onFinish: () -> Void

    @State private var step: OnboardingStep = .welcome
    @State private var didPickSource = false
    @State private var didPickDestination = false
    @State private var pickedPackID: String? = nil
    @State private var showingContactsPanel = false
    @State private var contactsPickedCount = 0

    enum OnboardingStep: Int, CaseIterable, Identifiable {
        case welcome = 0
        case source
        case tags
        case destination
        case shortcuts
        case done

        var id: Int { rawValue }

        var progress: Double {
            Double(rawValue) / Double(OnboardingStep.done.rawValue)
        }

        var title: String {
            switch self {
            case .welcome:      return "Welcome"
            case .source:       return "Shoot folder"
            case .tags:         return "Tags"
            case .destination:  return "Destination"
            case .shortcuts:    return "Shortcuts"
            case .done:         return "Ready"
            }
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                OnboardingHeader(
                    step: step,
                    canGoBack: step != .welcome && step != .done
                ) {
                    finish(skipped: true)
                } onBack: {
                    if let prev = OnboardingStep(rawValue: step.rawValue - 1) {
                        step = prev
                    }
                }
                .padding(.horizontal, Theme.Space.s24)
                .padding(.top, Theme.Space.s16)


                ScrollView {
                    stepBody
                        .frame(maxWidth: 720)
                        .padding(.horizontal, Theme.Space.s28)
                        .padding(.vertical, Theme.Space.s24)
                        .frame(maxWidth: .infinity)
                }

                Rectangle()
                    .fill(Theme.Color.surfaceDivider)
                    .frame(height: Theme.Stroke.hairline)

                OnboardingFooter(
                    step: step,
                    canAdvance: canAdvance,
                    onAdvance: advance
                )
                .padding(.horizontal, Theme.Space.s24)
                .padding(.vertical, Theme.Space.s14)
            }
            .frame(width: 820, height: 600)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.xl)
                    .fill(Theme.Color.surfaceBase)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.xl)
                    .stroke(Theme.Color.surfaceDivider, lineWidth: Theme.Stroke.hairline)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xl))
            .shadow(color: Theme.Color.overlayScrim.opacity(0.4), radius: 30, y: 12)
        }
        .onAppear {
            didPickSource = !viewModel.sourceDirectories.isEmpty || !viewModel.looseFiles.isEmpty
            didPickDestination = viewModel.destinationDirectory != nil
        }
    }

    // MARK: - Step content

    @ViewBuilder
    private var stepBody: some View {
        switch step {
        case .welcome:     welcomeStep
        case .source:      sourceStep
        case .tags:        tagsStep
        case .destination: destinationStep
        case .shortcuts:   shortcutsStep
        case .done:        doneStep
        }
    }

    // MARK: - Welcome

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s16) {
            Image(systemName: "sparkles")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(Theme.Color.accent)
                .padding(.bottom, Theme.Space.s4)

            Text("Welcome to DuckSort")
                .font(Theme.Font.title)
                .foregroundStyle(Theme.Color.textInverse)

            Text("Let's get your library set up. Five quick steps — each one maps to a place in the app you can revisit later from the sidebar.")
                .font(Theme.Font.subheadline)
                .foregroundStyle(Theme.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: Theme.Space.s10) {
                OnboardingBullet(
                    number: "1",
                    title: "Pick a shoot folder",
                    detail: "Sidebar → Toolbar → Add Source, or drag a folder into the window."
                )
                OnboardingBullet(
                    number: "2",
                    title: "Pick a tag pack",
                    detail: "Choose a preset built for your kind of shoot (weddings, portraits, cars, apparel, real estate, events, sports, products, or a neutral general set)."
                )
                OnboardingBullet(
                    number: "3",
                    title: "Choose a destination",
                    detail: "Toolbar → Choose Destination. This is where exports land."
                )
                OnboardingBullet(
                    number: "4",
                    title: "Optional: import contacts",
                    detail: "After picking a tag pack, you can pull names from a .vCard file into a People category."
                )
                OnboardingBullet(
                    number: "5",
                    title: "You're ready",
                    detail: "Start culling with rating keys (1–5), X to reject, U to clear pick, or any tag hotkey in the grid or large viewer."
                )
            }
            .padding(.top, Theme.Space.s4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Source

    private var sourceStep: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s14) {
            OnboardingStepHeader(
                eyebrow: "STEP 1 OF 5",
                title: "Choose your shoot folder",
                detail: "Point DuckSort at the folder of RAW/JPEG/HEIF photos you want to sort through. It scans recursively."
            )

            OnboardingWhereHint(
                icon: "sidebar.leading",
                text: "Later: Toolbar → Add Source Folder (⇧⌘O) — or just drag a folder onto the window."
            )

            HStack(spacing: Theme.Space.s12) {
                Button {
                    viewModel.addSourceDirectory()
                    didPickSource = true
                } label: {
                    Label("Choose Folder…", systemImage: "folder.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Theme.Color.accent)

                Button {
                    viewModel.importItems()
                    didPickSource = true
                } label: {
                    Label("Import Files…", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            OnboardingStatusRow(
                done: didPickSource,
                doneText: sourceSummary,
                pendingText: "No folder picked yet."
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Tags

    private var tagsStep: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s14) {
            OnboardingStepHeader(
                eyebrow: "STEP 2 OF 5",
                title: "Pick a tag pack for your shoots",
                detail: "Each pack is a curated set of categories and tags with single-key hotkeys. Pick the one closest to what you shoot, then customize from there."
            )

            OnboardingWhereHint(
                icon: "tag",
                text: "Later: Settings → Tags — full editor with hotkeys, colors, and contacts import."
            )

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: Theme.Space.s10),
                    GridItem(.flexible(), spacing: Theme.Space.s10),
                    GridItem(.flexible(), spacing: Theme.Space.s10)
                ],
                spacing: Theme.Space.s10
            ) {
                ForEach(TagPack.allPacks) { pack in
                    TagPackCard(
                        pack: pack,
                        isSelected: pickedPackID == pack.id
                    ) {
                        applyPack(pack)
                    }
                }
            }

            HStack(spacing: Theme.Space.s10) {
                Button {
                    if let names = VCardImport.promptAndParse(), !names.isEmpty {
                        addContactsAsPeople(names)
                        contactsPickedCount = names.count
                    }
                } label: {
                    Label("Import Contacts (.vCard)…", systemImage: "person.crop.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(pickedPackID == nil)

                if contactsPickedCount > 0 {
                    Button {
                        contactsPickedCount = 0
                        if let peopleID = viewModel.tagStore.categories
                            .first(where: { $0.name == "People" })?.id {
                            viewModel.tagStore.deleteCategory(id: peopleID)
                        }
                    } label: {
                        Label("Remove People", systemImage: "trash")
                            .foregroundStyle(Theme.Color.danger)
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.regular)
                }
            }

            if pickedPackID != nil {
                OnboardingStatusRow(
                    done: true,
                    doneText: "Tag pack applied (\(viewModel.tagStore.tags.count) tags in \(viewModel.tagStore.categories.count) categories)" +
                              (contactsPickedCount > 0
                               ? " · \(contactsPickedCount) contacts imported"
                               : ""),
                    pendingText: "Pick a tag pack to continue."
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Destination

    private var destinationStep: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s14) {
            OnboardingStepHeader(
                eyebrow: "STEP 3 OF 5",
                title: "Choose a destination folder",
                detail: "Exports (copy, move, or routed) land here. You can change it later or set up multiple destinations with routing rules."
            )

            OnboardingWhereHint(
                icon: "tray.and.arrow.down",
                text: "Later: Toolbar → Choose Destination — or per-export routing via Settings → Rules."
            )

            HStack(spacing: Theme.Space.s12) {
                Button {
                    viewModel.chooseDestinationDirectory()
                    didPickDestination = viewModel.destinationDirectory != nil
                } label: {
                    Label("Choose Destination…", systemImage: "tray.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Theme.Color.accent)

                if viewModel.destinationDirectory != nil {
                    Button {
                        viewModel.chooseDestinationDirectory()
                    } label: {
                        Label("Change…", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }

            OnboardingStatusRow(
                done: didPickDestination,
                doneText: viewModel.destinationDirectory?.path ?? "Destination set.",
                pendingText: "No destination picked yet."
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Shortcuts

    private var shortcutsStep: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s14) {
            OnboardingStepHeader(
                eyebrow: "STEP 4 OF 5",
                title: "Hotkeys & shortcuts",
                detail: "Tag pack hotkeys are set up for you. If anything collides with how you work, you can reset or remap them at any time."
            )

            OnboardingWhereHint(
                icon: "keyboard.badge.ellipsis",
                text: "Later: Settings → Shortcuts — remap app actions. Settings → Tags — remap per-tag hotkeys."
            )

            VStack(alignment: .leading, spacing: Theme.Space.s8) {
                HStack(spacing: Theme.Space.s10) {
                    Image(systemName: "keyboard")
                        .foregroundStyle(Theme.Color.accent)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Built-in culling keys")
                            .font(Theme.Font.bodyBold)
                            .foregroundStyle(Theme.Color.textInverse)
                        Text("1–5 rate · X reject · U clear pick · Z flag · Space open viewer · ←/→ navigate · ⇧+click range-select · drag empty area to marquee-select.")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, Theme.Space.s12)
            .padding(.vertical, Theme.Space.s10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.m)
                    .fill(Theme.Color.surfaceRaised.opacity(0.6))
            )

            VStack(alignment: .leading, spacing: Theme.Space.s6) {
                Text("If a hotkey is in your way:")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Color.textPrimary)
                HStack(spacing: Theme.Space.s10) {
                    Button {
                        viewModel.tagStore.clearAllHotkeys()
                    } label: {
                        Label("Reset all tag hotkeys", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .disabled(viewModel.tagStore.tags.isEmpty)

                    Button {
                        viewModel.tagStore.clearAllTags()
                        contactsPickedCount = 0
                        pickedPackID = nil
                    } label: {
                        Label("Clear all tags", systemImage: "trash")
                            .foregroundStyle(Theme.Color.danger)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .tint(Theme.Color.danger)
                    .disabled(viewModel.tagStore.tags.isEmpty)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Done

    private var doneStep: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(Theme.Color.success)
                .padding(.bottom, Theme.Space.s4)

            Text("You're ready!")
                .font(Theme.Font.title)
                .foregroundStyle(Theme.Color.textInverse)

            Text("Here's what you set up. Everything below can be changed later from the sidebar or Settings:")
                .font(Theme.Font.subheadline)
                .foregroundStyle(Theme.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: Theme.Space.s8) {
                OnboardingRecapRow(
                    icon: "folder",
                    title: "Shoot folder",
                    detail: sourceSummary
                )
                OnboardingRecapRow(
                    icon: "tag",
                    title: "Tag pack",
                    detail: pickedPackDetail
                )
                OnboardingRecapRow(
                    icon: "tray.and.arrow.down",
                    title: "Destination",
                    detail: viewModel.destinationDirectory?.lastPathComponent ?? "Not set"
                )
            }
            .padding(.top, Theme.Space.s4)

            VStack(alignment: .leading, spacing: 6) {
                OnboardingRecapLink(
                    icon: "tag",
                    label: "Customize tags & hotkeys",
                    detail: "Settings → Tags"
                )
                OnboardingRecapLink(
                    icon: "folder.badge.gearshape",
                    label: "Edit routing rules",
                    detail: "Settings → Rules"
                )
                OnboardingRecapLink(
                    icon: "c.circle",
                    label: "Set up copyright / IPTC for exports",
                    detail: "Settings → Copyright"
                )
                OnboardingRecapLink(
                    icon: "info.circle",
                    label: "See advanced EXIF in inspector",
                    detail: "View → Show Advanced EXIF (⇧⌘E)"
                )
            }
            .padding(.top, Theme.Space.s8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Footer actions

    private var canAdvance: Bool {
        switch step {
        case .welcome:      return true
        case .source:       return didPickSource
        case .tags:         return pickedPackID != nil && !viewModel.tagStore.tags.isEmpty
        case .destination:  return didPickDestination
        case .shortcuts:    return true
        case .done:         return true
        }
    }

    private var sourceSummary: String {
        let dirs = viewModel.sourceDirectories.count
        let loose = viewModel.looseFiles.count
        switch (dirs, loose) {
        case (0, 0): return "No folder picked yet."
        case (1, 0): return "1 source folder picked."
        case (let d, 0): return "\(d) source folders picked."
        case (0, let l): return "\(l) file\(l == 1 ? "" : "s") imported."
        case (let d, let l): return "\(d) folder\(d == 1 ? "" : "s") + \(l) file\(l == 1 ? "" : "s")."
        }
    }

    private var pickedPackDetail: String {
        if let id = pickedPackID, let pack = TagPack.pack(id: id) {
            return "\(pack.name) · \(viewModel.tagStore.tags.count) tags"
        }
        return "Not picked"
    }

    private func advance() {
        switch step {
        case .welcome:     step = .source
        case .source:      step = .tags
        case .tags:        step = .destination
        case .destination: step = .shortcuts
        case .shortcuts:   step = .done
        case .done:         finish(skipped: false)
        }
    }

    private func applyPack(_ pack: TagPackTemplate) {
        // Route through the library so the user's active-pack id is
        // persisted alongside the freshly-applied state.
        viewModel.switchTagPack(id: pack.id)
        pickedPackID = pack.id
        contactsPickedCount = 0
    }

    private func addContactsAsPeople(_ names: [String]) {
        // Make sure a People category exists in the active pack.
        if viewModel.tagStore.categories.first(where: { $0.name == "People" }) == nil {
            let new = viewModel.tagStore.addCategory(name: "People")
            // Re-apply the current pack so the new category is filled with
            // its People tags (some packs include People tags, some don't).
            if let id = pickedPackID, let pack = TagPack.pack(id: id) {
                viewModel.tagStore.applyPack(pack)
                _ = new
            }
        }

        let peopleID = viewModel.tagStore.categories
            .first(where: { $0.name == "People" })?.id
            ?? viewModel.tagStore.addCategory(name: "People").id

        let existing = Set(viewModel.tagStore.tags
            .filter { $0.categoryID == peopleID }
            .map { $0.name.lowercased() })

        for name in names where !existing.contains(name.lowercased()) {
            _ = viewModel.tagStore.addTag(name: name, categoryID: peopleID)
        }
    }

    private func finish(skipped: Bool) {
        // Finishing counts as completing — the user has seen the wizard
        // and can re-launch it any time from Help → Show Welcome Guide.
        preferences.hasCompletedOnboarding = true
        preferences.save()
        onFinish()
    }
}

// MARK: - Subviews

private struct OnboardingHeader: View {
    let step: OnboardingFlow.OnboardingStep
    let canGoBack: Bool
    let onSkip: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: Theme.Space.s10) {
            HStack {
                if canGoBack {
                    Button(action: onBack) {
                        Label("Back", systemImage: "chevron.left")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Spacer()

                Text(step.title)
                    .font(Theme.Font.bodyBold)
                    .foregroundStyle(Theme.Color.textInverse)

                Spacer()

                Button("Skip") { onSkip() }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .font(Theme.Font.caption)
            }

            HStack(spacing: 6) {
                ForEach(OnboardingFlow.OnboardingStep.allCases) { s in
                    Capsule()
                        .fill(s.rawValue <= step.rawValue
                              ? Theme.Color.accent
                              : Theme.Color.surfaceRaised)
                        .frame(height: 4)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

private struct OnboardingFooter: View {
    let step: OnboardingFlow.OnboardingStep
    let canAdvance: Bool
    let onAdvance: () -> Void

    var body: some View {
        HStack {
            Spacer()
            Button(action: onAdvance) {
                HStack(spacing: Theme.Space.s6) {
                    Text(buttonLabel)
                    Image(systemName: buttonIcon)
                }
                .frame(minWidth: 140)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Theme.Color.accent)
            .disabled(!canAdvance)
        }
    }

    private var buttonLabel: String {
        switch step {
        case .welcome:     return "Get Started"
        case .source:      return "Next: Tags"
        case .tags:        return "Next: Destination"
        case .destination: return "Next: Shortcuts"
        case .shortcuts:   return "Next: Finish"
        case .done:        return "Start Using DuckSort"
        }
    }

    private var buttonIcon: String {
        switch step {
        case .welcome, .source, .tags, .destination, .shortcuts:
            return "arrow.right"
        case .done:
            return "checkmark"
        }
    }
}

private struct OnboardingStepHeader: View {
    let eyebrow: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s4) {
            Text(eyebrow)
                .font(Theme.Font.caption2)
                .tracking(0.5)
                .foregroundStyle(Theme.Color.accent)
            Text(title)
                .font(Theme.Font.headline)
                .foregroundStyle(Theme.Color.textInverse)
            Text(detail)
                .font(Theme.Font.subheadline)
                .foregroundStyle(Theme.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// "Later: Settings → Tags — full editor with hotkeys, colors…" Callout
/// that tells the user where this setting lives in the app, so the
/// wizard doubles as a tour.
private struct OnboardingWhereHint: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.s8) {
            Image(systemName: icon)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.accent)
                .frame(width: 16)
            Text(text)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Theme.Space.s10)
        .padding(.vertical, Theme.Space.s8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.m)
                .fill(Theme.Color.surfaceRaised.opacity(0.4))
        )
    }
}

private struct OnboardingBullet: View {
    let number: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.s12) {
            Text(number)
                .font(Theme.Font.bodyBold)
                .foregroundStyle(Theme.Color.accent)
                .frame(width: 22, alignment: .center)
                .padding(.vertical, 2)
                .background(
                    Circle().fill(Theme.Color.accent.opacity(0.12))
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Font.bodyBold)
                    .foregroundStyle(Theme.Color.textInverse)
                Text(detail)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct OnboardingStatusRow: View {
    let done: Bool
    let doneText: String
    let pendingText: String

    var body: some View {
        HStack(spacing: Theme.Space.s8) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(done ? Theme.Color.success : Theme.Color.textTertiary)
            Text(done ? doneText : pendingText)
                .font(Theme.Font.caption)
                .foregroundStyle(done ? Theme.Color.textPrimary : Theme.Color.textTertiary)
                .lineLimit(2)
                .truncationMode(.middle)
        }
        .padding(.horizontal, Theme.Space.s12)
        .padding(.vertical, Theme.Space.s10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.m)
                .fill(done
                      ? Theme.Color.success.opacity(0.08)
                      : Theme.Color.surfaceRaised.opacity(0.5))
        )
    }
}

private struct OnboardingRecapRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: Theme.Space.s12) {
            Image(systemName: icon)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Color.accent)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Font.caption)
                    .tracking(0.3)
                    .foregroundStyle(Theme.Color.textSecondary)
                Text(detail)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Color.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }
}

private struct OnboardingRecapLink: View {
    let icon: String
    let label: String
    let detail: String

    var body: some View {
        HStack(spacing: Theme.Space.s10) {
            Image(systemName: icon)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.textSecondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.textInverse)
                Text(detail)
                    .font(Theme.Font.caption2)
                    .foregroundStyle(Theme.Color.textSecondary)
            }
        }
        .padding(.horizontal, Theme.Space.s10)
        .padding(.vertical, Theme.Space.s6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.m)
                .fill(Theme.Color.surfaceRaised.opacity(0.5))
        )
    }
}

private struct TagPackCard: View {
    let pack: TagPackTemplate
    let isSelected: Bool
    let onSelect: () -> Void

    /// Fixed card height so all 9 pack cards line up in a perfect 3×3 grid
    /// regardless of how long the tagline or how many tags a pack has.
    private static let cardHeight: CGFloat = 132

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: Theme.Space.s6) {
                HStack(spacing: Theme.Space.s6) {
                    Image(systemName: pack.systemImage)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color(hex: pack.accentColor) ?? .accentColor)
                    Text(pack.name)
                        .font(Theme.Font.bodyBold)
                        .foregroundStyle(Theme.Color.textInverse)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Theme.Color.success)
                    }
                }
                Text(pack.tagline)
                    .font(Theme.Font.caption2)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    Image(systemName: "tag")
                        .font(.system(size: 10))
                    Text("\(pack.tags.count) tags · \(pack.categories.count) categories")
                        .font(Theme.Font.caption2)
                        .foregroundStyle(Theme.Color.textTertiary)
                    Spacer(minLength: 0)
                }
            }
            .padding(Theme.Space.s10)
            .frame(maxWidth: .infinity, minHeight: Self.cardHeight, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.m)
                    .fill(Theme.Color.surfaceRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.m)
                    .stroke(isSelected ? Theme.Color.accent : Theme.Color.surfaceDivider,
                            lineWidth: isSelected ? 2 : Theme.Stroke.hairline)
            )
        }
        .buttonStyle(.plain)
    }
}
