//
//  CaptionEditorView.swift
//  DuckSort
//
//  Multi-line caption editor bound to a PhotoSet. Writes to dc:description
//  in the XMP sidecar via the view model, with debounced auto-save.
//

import SwiftUI

struct CaptionEditorView: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel
    let photoSet: PhotoSet

    @State private var captionDraft: String = ""
    @State private var loadedCaptionKey: UUID? = nil
    @State private var commitTask: Task<Void, Never>? = nil
    @FocusState private var isCaptionFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s8) {
            HStack(spacing: Theme.Space.s6) {
                Image(systemName: "text.alignleft")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.textSecondary)
                Text("Caption")
                    .font(Theme.Font.subheadline)
                    .foregroundStyle(Theme.Color.textPrimary)
                Spacer()
                if !captionDraft.isEmpty {
                    Button("Clear") {
                        captionDraft = ""
                        commitCaptionChange()
                    }
                    .buttonStyle(.plain)
                    .font(Theme.Font.caption2)
                    .foregroundStyle(Theme.Color.textSecondary)
                }
            }

            TextEditor(text: $captionDraft)
                .font(Theme.Font.caption)
                .scrollContentBackground(.hidden)
                .padding(Theme.Space.s6)
                .frame(minHeight: 70, maxHeight: 140)
                .background(Color(NSColor.textBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: Theme.Radius.m))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.m)
                        .stroke(isCaptionFocused ? Theme.Color.accent : Theme.Color.separator,
                                lineWidth: isCaptionFocused ? 1.5 : Theme.Stroke.hairline)
                )
                .focused($isCaptionFocused)
                .focusEffectDisabled()
                .onChange(of: captionDraft) { _, _ in
                    scheduleCommit()
                }

            Text(captionDraft.isEmpty
                 ? "Saved as dc:description in the XMP sidecar and searchable from the sidebar. Double-click outside to release focus."
                 : "Saved as dc:description in the XMP sidecar.")
                .font(Theme.Font.caption2)
                .foregroundStyle(Theme.Color.textSecondary)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            commitCaptionChange()
            isCaptionFocused = false
        }
        .background {
            // Hidden button that grabs Escape to release focus without
            // interfering with the global Esc-to-close-viewer shortcut.
            Button("") { isCaptionFocused = false }
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        .onChange(of: photoSet.id) { _, _ in
            loadCaptionIfNeeded()
        }
        .onAppear {
            loadCaptionIfNeeded()
        }
    }

    private func loadCaptionIfNeeded() {
        guard photoSet.id != loadedCaptionKey else { return }
        commitTask?.cancel()
        loadedCaptionKey = photoSet.id
        captionDraft = viewModel.caption(for: photoSet) ?? ""
        isCaptionFocused = false
    }

    private func scheduleCommit() {
        commitTask?.cancel()
        let snapshot = captionDraft
        commitTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            if Task.isCancelled { return }
            if captionDraft == snapshot {
                viewModel.setCaption(snapshot, for: photoSet.id)
            }
        }
    }

    private func commitCaptionChange() {
        commitTask?.cancel()
        viewModel.setCaption(captionDraft, for: photoSet.id)
    }
}