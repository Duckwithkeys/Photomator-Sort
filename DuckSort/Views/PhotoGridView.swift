//
//  PhotoGridView.swift
//  PhotomatorSort
//

import SwiftUI

struct PhotoGridView: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel

    // Keep these in sync with `columns` and the grid padding below so the
    // computed column count matches what LazyVGrid actually renders.
    private static let minItemWidth: CGFloat = 180
    private static let gridSpacing: CGFloat = 14
    private static let horizontalPadding: CGFloat = 20

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: Self.minItemWidth), spacing: Self.gridSpacing)]
    }

    private static func columnCount(forWidth width: CGFloat) -> Int {
        let available = width - horizontalPadding * 2
        guard available > 0 else { return 1 }
        let count = Int(floor((available + gridSpacing) / (minItemWidth + gridSpacing)))
        return max(1, count)
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 14) {
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
                                }
                            )
                            .id(photoSet.id)
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
                    .padding(.horizontal, 20)
                    .padding(.top, 44)
                    .padding(.bottom, 16)
                }
                .onChange(of: viewModel.focusedPhotoIndex) { _, newIndex in
                    if newIndex >= 0 && newIndex < viewModel.filteredPhotoSets.count {
                        let targetID = viewModel.filteredPhotoSets[newIndex].id
                        withAnimation(.easeInOut(duration: 0.15)) {
                            scrollProxy.scrollTo(targetID)
                        }
                    }
                }
            }
            .onAppear {
                viewModel.gridColumnCount = Self.columnCount(forWidth: geometry.size.width)
            }
            .onChange(of: geometry.size.width) { _, newWidth in
                viewModel.gridColumnCount = Self.columnCount(forWidth: newWidth)
            }
        }
        .overlay(alignment: .top) {
            if viewModel.isScanning {
                ProgressView("Scanning subfolders...")
                    .padding(12)
                    .background(PhotomatorTheme.cellBackground, in: RoundedRectangle(cornerRadius: 8))
                    .padding(.top, 48)
            }
        }
    }
}
