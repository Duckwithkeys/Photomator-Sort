//
//  FilmstripView.swift
//  DuckSort
//

import SwiftUI

struct FilmstripView: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel

    private static let thumbSize = CGSize(width: 72, height: 48)

    var body: some View {
        HStack(spacing: 0) {
            ScrollViewReader { scrollProxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: Theme.Space.s8) {
                        ForEach(Array(viewModel.filteredPhotoSets.enumerated()), id: \.element.id) { index, photoSet in
                            let isFocused = index == viewModel.focusedPhotoIndex
                            let previewURL = photoSet.preferredPreviewURL

                            FilmstripThumbnailCell(
                                photoSet: photoSet,
                                previewURL: previewURL,
                                isFocused: isFocused,
                                onSelect: {
                                    withAnimation(.easeOut(duration: 0.12)) {
                                        viewModel.focusedPhotoIndex = index
                                    }
                                }
                            )
                            .id(photoSet.id)
                        }
                    }
                    .padding(.horizontal, Theme.Space.s14)
                    .padding(.vertical, Theme.Space.s8)
                }
                .onChange(of: viewModel.focusedPhotoIndex) { _, newIndex in
                    if newIndex >= 0 && newIndex < viewModel.filteredPhotoSets.count {
                        let targetID = viewModel.filteredPhotoSets[newIndex].id
                        scrollProxy.scrollTo(targetID, anchor: .center)
                    }
                    prefetchNeighbors(around: newIndex)
                }
                .onAppear {
                    if viewModel.focusedPhotoIndex >= 0 && viewModel.focusedPhotoIndex < viewModel.filteredPhotoSets.count {
                        let targetID = viewModel.filteredPhotoSets[viewModel.focusedPhotoIndex].id
                        scrollProxy.scrollTo(targetID, anchor: .center)
                    }
                    prefetchNeighbors(around: viewModel.focusedPhotoIndex)
                }
            }

            let total = viewModel.filteredPhotoSets.count
            if total > 0 {
                Text("\(viewModel.focusedPhotoIndex + 1) / \(total)")
                    .font(Theme.Font.monoCaption)
                    .foregroundStyle(Theme.Color.textInverse)
                    .padding(.horizontal, Theme.Space.s8)
                    .padding(.vertical, Theme.Space.s4)
                    .background(Theme.Color.overlayDim, in: Capsule())
                    .padding(.trailing, Theme.Space.s12)
                    .padding(.leading, Theme.Space.s16)
            }
        }
        .frame(height: Theme.Space.s64)
        .background(Theme.Color.footerBackground)
    }

    /// Warm the thumbnail cache for photos around the focused index so
    /// scrubbing the filmstrip reveals fully decoded thumbs instantly
    /// instead of waiting for each `ThumbnailView.task` to kick off.
    private func prefetchNeighbors(around index: Int) {
        let list = viewModel.filteredPhotoSets
        guard !list.isEmpty else { return }
        let window = 30
        let start = max(0, index - window)
        let end = min(list.count - 1, index + window)
        guard start <= end else { return }
        let size = Self.thumbSize
        for i in start...end {
            guard let url = list[i].preferredPreviewURL else { continue }
            Task.detached(priority: .utility) {
                _ = await ThumbnailService.shared.thumbnail(for: url, size: size)
            }
        }
    }
}

struct FilmstripThumbnailCell: View {
    let photoSet: PhotoSet
    let previewURL: URL?
    let isFocused: Bool
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            ZStack(alignment: .bottomTrailing) {
                ThumbnailView(url: previewURL, size: Self.thumbSize, cornerRadius: Theme.Radius.s)
                    .frame(width: Self.thumbSize.width, height: Self.thumbSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.s))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.s)
                            .stroke(
                                isFocused ? Theme.Color.accent
                                          : (isHovered ? Theme.Color.textInverse.opacity(0.3) : Color.clear),
                                lineWidth: isFocused ? Theme.Stroke.heavy : Theme.Stroke.hairline
                            )
                    )

                HStack(spacing: Theme.Space.s4) {
                    if photoSet.hasEdit {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Theme.Color.textInverse)
                            .padding(Theme.Space.s4)
                            .background(Theme.Color.warning, in: Circle())
                    }
                    if photoSet.isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Theme.Color.textInverse)
                            .padding(Theme.Space.s4)
                            .background(Theme.Color.success, in: Circle())
                    }
                }
                .padding(Theme.Space.s2)
            }
            .frame(width: Self.thumbSize.width, height: Self.thumbSize.height)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovered = hovering }
        }
    }

    private static let thumbSize = CGSize(width: 72, height: 48)
}
