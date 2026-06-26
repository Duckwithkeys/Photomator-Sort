//
//  XMPTagInspectorView.swift
//  DuckSort
//
//  Small floating overlay (View → "XMP Tags Not in Active Pack…") that
//  scans every loaded photo's XMP sidecar and lists any `dc:subject`
//  keywords that are NOT defined as tags in the active pack. Useful when
//  users inherit XMPs from another catalog and want to know which keywords
//  are being silently ignored.
//

import SwiftUI

struct XMPTagInspectorView: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel
    let onClose: () -> Void

    @State private var diff: PhotoLibraryViewModel.XMPTagDiff?
    @State private var isLoading = false
    @State private var lastScanError: String?
    @State private var searchText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider().overlay(Theme.Color.surfaceDivider)

            if isLoading {
                loadingState
            } else if let diff {
                content(diff: diff)
            } else {
                emptyState
            }
        }
        .background(Theme.Color.surfaceBase)
        .task { await rescan() }
        .onChange(of: viewModel.activeTagPack.id) { _, _ in
            Task { await rescan() }
        }
    }

    // MARK: - Sub-views

    private var header: some View {
        HStack(alignment: .top, spacing: Theme.Space.s12) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.m)
                    .fill(Theme.Color.warning.opacity(0.18))
                    .frame(width: 36, height: 36)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.Color.warning)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("XMP Tags Not in Active Pack")
                    .font(Theme.Font.bodyBold)
                    .foregroundStyle(Theme.Color.textInverse)
                Text(diffHeaderLine)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button {
                Task { await rescan() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Color.accent)
                    .padding(6)
                    .background(
                        Circle().fill(Theme.Color.surfaceRaised)
                    )
            }
            .buttonStyle(.plain)
            .help("Rescan sidecars")
            .disabled(isLoading)
        }
        .padding(.horizontal, Theme.Space.s16)
        .padding(.vertical, Theme.Space.s12)
    }

    private var diffHeaderLine: String {
        guard let diff else { return "Scanning…" }
        if diff.orphanTags.isEmpty {
            return "Every keyword in your XMP sidecars matches a tag in “\(diff.activePackName)”. Nothing to clean up."
        }
        return "\(diff.orphanTags.count) keyword\(diff.orphanTags.count == 1 ? "" : "s") in your XMP sidecars aren’t defined in “\(diff.activePackName)”. They will be ignored unless you add them to the pack."
    }

    private var loadingState: some View {
        VStack(spacing: Theme.Space.s12) {
            ProgressView()
            Text("Reading sidecars…")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Space.s8) {
            Image(systemName: "tray")
                .font(.system(size: 28))
                .foregroundStyle(Theme.Color.textTertiary)
            Text("No photo library loaded.")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.textSecondary)
            if let lastScanError {
                Text(lastScanError)
                    .font(Theme.Font.caption2)
                    .foregroundStyle(Theme.Color.danger)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Space.s24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func content(diff: PhotoLibraryViewModel.XMPTagDiff) -> some View {
        VStack(spacing: 0) {
            searchField

            if diff.orphanTags.isEmpty {
                cleanState(diff: diff)
            } else {
                orphanList(diff: diff)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: Theme.Space.s8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.Color.textTertiary)
                .font(Theme.Font.caption)
            TextField("Filter keywords", text: $searchText)
                .textFieldStyle(.plain)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.textInverse)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.Color.textTertiary)
                        .font(Theme.Font.caption)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.Space.s10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.s)
                .fill(Theme.Color.surfaceRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.s)
                .stroke(Theme.Color.surfaceDivider, lineWidth: Theme.Stroke.hairline)
        )
        .padding(.horizontal, Theme.Space.s16)
        .padding(.top, Theme.Space.s10)
        .padding(.bottom, Theme.Space.s6)
    }

    private func cleanState(diff: PhotoLibraryViewModel.XMPTagDiff) -> some View {
        VStack(spacing: Theme.Space.s10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 36))
                .foregroundStyle(Theme.Color.success)
            Text("All XMP keywords are covered.")
                .font(Theme.Font.bodyBold)
                .foregroundStyle(Theme.Color.textInverse)
            Text("Scanned \(diff.totalPhotosScanned) photo set\(diff.totalPhotosScanned == 1 ? "" : "s").")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func orphanList(diff: PhotoLibraryViewModel.XMPTagDiff) -> some View {
        let usageIndex: [String: [PhotoSet]] = viewModel.photoSets.reduce(into: [:]) { acc, set in
            if let names = diff.orphanUsage[set.id] {
                for n in names { acc[n, default: []].append(set) }
            }
        }
        let filtered = filteredOrphans(diff: diff)
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.Space.s8) {
                ForEach(filtered, id: \.self) { name in
                    OrphanTagRow(
                        name: name,
                        usage: usageIndex[name] ?? [],
                        onAddToPack: { addOrphanToActivePack(name) }
                    )
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity.combined(with: .scale(scale: 0.92))
                    ))
                }
                if filtered.isEmpty {
                    Text("No matches for “\(searchText)”.")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Color.textTertiary)
                        .padding(.top, Theme.Space.s16)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .padding(.horizontal, Theme.Space.s16)
            .padding(.bottom, Theme.Space.s12)
            .animation(.easeInOut(duration: 0.18), value: filtered)
        }
    }

    private func filteredOrphans(diff: PhotoLibraryViewModel.XMPTagDiff) -> [String] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return diff.orphanTags }
        return diff.orphanTags.filter { $0.lowercased().contains(q) }
    }

    // MARK: - Actions

    private func rescan() async {
        isLoading = true
        lastScanError = nil
        let result = await viewModel.computeXMPTagDiff()
        await MainActor.run {
            diff = result
            isLoading = false
        }
    }

    private func addOrphanToActivePack(_ name: String) {
        let categories = viewModel.tagStore.categories
        let preferred = categories.first(where: { $0.name.localizedCaseInsensitiveCompare("Subject") == .orderedSame })
            ?? categories.first
        guard let categoryID = preferred?.id else { return }

        // 1. Add the tag to the store up front. TagStore.tags is @Published
        //    and the view model forwards objectWillChange, so the sidebar
        //    re-renders on the very next runloop tick.
        viewModel.tagStore.addTag(name: name, categoryID: categoryID)

        // 2. Optimistically remove the keyword from the local diff so the
        //    orphan row disappears instantly — the user shouldn't have to
        //    wait for a full XMP rescan to see the result of their action.
        if var current = diff {
            current.orphanTags.removeAll { $0.caseInsensitiveCompare(name) == .orderedSame }
            var trimmedUsage = current.orphanUsage
            for (key, var names) in trimmedUsage {
                names.removeAll { $0.caseInsensitiveCompare(name) == .orderedSame }
                if names.isEmpty {
                    trimmedUsage.removeValue(forKey: key)
                } else {
                    trimmedUsage[key] = names
                }
            }
            current.orphanUsage = trimmedUsage
            diff = current
        }

        // 3. Kick off a full rescan in the background to catch any other
        //    orphans (or to surface cases where the XMP tag count for some
        //    photo changed). The optimistic update above already made the
        //    UI feel instant; this just keeps the data honest.
        Task { await rescan() }
    }
}

private struct OrphanTagRow: View {
    let name: String
    let usage: [PhotoSet]
    let onAddToPack: () -> Void
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: Theme.Space.s8) {
                Image(systemName: "tag")
                    .foregroundStyle(Theme.Color.warning)
                    .font(Theme.Font.caption)
                Text(name)
                    .font(Theme.Font.bodyBold)
                    .foregroundStyle(Theme.Color.textInverse)
                    .lineLimit(1)
                Spacer()
                if isHovered {
                    Button("Add to Pack", action: onAddToPack)
                        .buttonStyle(.borderless)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Color.accent)
                }
            }
            Text(usageLine)
                .font(Theme.Font.caption2)
                .foregroundStyle(Theme.Color.textSecondary)
                .lineLimit(2)
        }
        .padding(.horizontal, Theme.Space.s12)
        .padding(.vertical, Theme.Space.s8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.s)
                .fill(isHovered ? Theme.Color.surfaceRaised.opacity(0.9) : Theme.Color.surfaceRaised.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.s)
                .stroke(Theme.Color.surfaceDivider, lineWidth: Theme.Stroke.hairline)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) { isHovered = hovering }
        }
        .contextMenu {
            Button("Add “\(name)” to Active Pack", action: onAddToPack)
            if let first = usage.first {
                Text("Used in \(usage.count) photo\(usage.count == 1 ? "" : "s"), e.g. \(first.displayName)")
            } else {
                Text("Defined in XMP but not yet on any loaded photo")
            }
        }
    }

    private var usageLine: String {
        if usage.isEmpty {
            return "Defined in XMP but not yet on any loaded photo."
        }
        let preview = usage.prefix(3).map(\.displayName).joined(separator: ", ")
        let extra = usage.count > 3 ? " +\(usage.count - 3) more" : ""
        return "On \(usage.count) photo\(usage.count == 1 ? "" : "s") — \(preview)\(extra)"
    }
}
