//
//  FilmstripView.swift
//  PhotomatorSort
//

import SwiftUI

struct FilmstripView: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel

    var body: some View {
        HStack(spacing: 0) {
            ScrollViewReader { scrollProxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 8) {
                        ForEach(Array(viewModel.filteredPhotoSets.enumerated()), id: \.element.id) { index, photoSet in
                            let isFocused = index == viewModel.focusedPhotoIndex
                            let isNearFocus = viewModel.nearFocusedIds.contains(photoSet.id)
                            let previewURL = isNearFocus ? photoSet.preferredPreviewURL : nil
                            
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
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
                .onChange(of: viewModel.focusedPhotoIndex) { _, newIndex in
                    DispatchQueue.main.async {
                        if newIndex >= 0 && newIndex < viewModel.filteredPhotoSets.count {
                            let targetID = viewModel.filteredPhotoSets[newIndex].id
                            withAnimation(.easeInOut(duration: 0.15)) {
                                scrollProxy.scrollTo(targetID, anchor: .center)
                            }
                        }
                    }
                }
                .onAppear {
                    DispatchQueue.main.async {
                        if viewModel.focusedPhotoIndex >= 0 && viewModel.focusedPhotoIndex < viewModel.filteredPhotoSets.count {
                            let targetID = viewModel.filteredPhotoSets[viewModel.focusedPhotoIndex].id
                            scrollProxy.scrollTo(targetID, anchor: .center)
                        }
                    }
                }
            }
            
            // HUD counter on the right
            let total = viewModel.filteredPhotoSets.count
            if total > 0 {
                Text("\(viewModel.focusedPhotoIndex + 1) / \(total)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.6), in: Capsule())
                    .padding(.trailing, 12)
                    .padding(.leading, 16)
            }
        }
        .frame(height: 64)
        .background(Color(red: 0.12, green: 0.12, blue: 0.12))
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
                // Thumbnail
                ThumbnailView(url: previewURL, size: CGSize(width: 120, height: 80), cornerRadius: 4)
                    .frame(width: 72, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(
                                isFocused ? Color.accentColor : (isHovered ? Color.white.opacity(0.3) : Color.clear),
                                lineWidth: isFocused ? 2.5 : 1
                            )
                    )
                    .scaleEffect(isHovered ? 1.04 : 1.0)
                    .shadow(color: isFocused ? Color.accentColor.opacity(0.4) : (isHovered ? Color.black.opacity(0.3) : .clear), radius: isHovered ? 4 : 0)

                // Selection / Edit Badges overlay
                HStack {
                    if photoSet.hasEdit {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(3)
                            .background(Color.orange, in: Circle())
                    }
                    Spacer()
                    if photoSet.isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(3)
                            .background(Color.green, in: Circle())
                    }
                }
                .padding(2)
            }
            .frame(width: 72, height: 48)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }
}
