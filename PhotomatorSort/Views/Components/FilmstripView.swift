//
//  FilmstripView.swift
//  PhotomatorSort
//

import SwiftUI

struct FilmstripView: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(viewModel.filteredPhotoSets.enumerated()), id: \.element.id) { index, photoSet in
                        let isFocused = index == viewModel.focusedPhotoIndex
                        
                        Button {
                            withAnimation(.easeOut(duration: 0.12)) {
                                viewModel.focusedPhotoIndex = index
                            }
                        } label: {
                            ZStack(alignment: .bottomTrailing) {
                                // Thumbnail
                                ThumbnailView(url: photoSet.preferredPreviewURL, size: CGSize(width: 120, height: 80))
                                    .frame(width: 72, height: 48)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(
                                                isFocused ? Color.accentColor : Color.clear,
                                                lineWidth: isFocused ? 2.5 : 0
                                            )
                                    )
                                    .shadow(color: isFocused ? Color.accentColor.opacity(0.4) : Color.clear, radius: 4)

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
                        .id(index)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .onChange(of: viewModel.focusedPhotoIndex) { _, newIndex in
                withAnimation(.easeInOut(duration: 0.15)) {
                    scrollProxy.scrollTo(newIndex, anchor: .center)
                }
            }
            .onAppear {
                scrollProxy.scrollTo(viewModel.focusedPhotoIndex, anchor: .center)
            }
        }
        .frame(height: 64)
    }
}
