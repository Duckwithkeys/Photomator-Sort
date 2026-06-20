//
//  PhotoGridView.swift
//  PhotomatorSort
//

import SwiftUI

struct PhotoGridView: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel
    @State private var gridWidth: CGFloat = 800

    private let columns = [
        GridItem(.adaptive(minimum: 208), spacing: 18)
    ]

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(Array(viewModel.filteredPhotoSets.enumerated()), id: \.element.id) { index, photoSet in
                            let isFocused = index == viewModel.focusedPhotoIndex
                            PhotoSetCell(
                                photoSet: photoSet,
                                tags: viewModel.assignedTags(for: photoSet),
                                isFocusedGridItem: isFocused,
                                isJpegOnlyMode: viewModel.isJpegOnlyMode,
                                toggleSelection: {
                                    viewModel.focusedPhotoIndex = index
                                    viewModel.toggleSelection(for: photoSet.id)
                                },
                                openBigView: {
                                    viewModel.focusedPhotoIndex = index
                                    viewModel.openLargeImageViewer()
                                }
                            )
                            .id(index)
                            .simultaneousGesture(
                                TapGesture().onEnded {
                                    viewModel.focusedPhotoIndex = index
                                }
                            )
                            .simultaneousGesture(
                                TapGesture(count: 2).onEnded {
                                    viewModel.focusedPhotoIndex = index
                                    viewModel.openLargeImageViewer()
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 22)
                }
                .onChange(of: viewModel.focusedPhotoIndex) { _, newIndex in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        scrollProxy.scrollTo(newIndex)
                    }
                }
            }
            .onAppear {
                gridWidth = geometry.size.width
            }
            .onChange(of: geometry.size.width) { _, newWidth in
                gridWidth = newWidth
            }
        }
        .overlay(alignment: .top) {
            if viewModel.isScanning {
                ProgressView("Scanning subfolders...")
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding(.top, 18)
            }
        }
    }
}
