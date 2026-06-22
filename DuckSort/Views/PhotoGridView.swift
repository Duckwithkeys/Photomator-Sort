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
        guard width.isFinite else { return 1 }
        let available = width - horizontalPadding * 2
        guard available > 0 && available.isFinite else { return 1 }
        let divisor = minItemWidth + gridSpacing
        guard divisor > 0 else { return 1 }
        let val = (available + gridSpacing) / divisor
        guard val.isFinite else { return 1 }
        let count = Int(floor(val))
        return max(1, count)
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(viewModel.filterRule.rawValue)
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(PhotomatorTheme.textPrimary)
                            
                            Text("\(viewModel.filteredPhotoSets.count) item\(viewModel.filteredPhotoSets.count == 1 ? "" : "s")")
                                .font(.footnote)
                                .foregroundStyle(PhotomatorTheme.textSecondary)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 44)
                        .padding(.bottom, 12)

                        Rectangle()
                            .fill(PhotomatorTheme.selectedBlue)
                            .frame(height: 1)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 16)

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
                                        NSApp.keyWindow?.makeFirstResponder(nil)
                                    }
                                )
                                .id(photoSet.id)
                                .simultaneousGesture(
                                    TapGesture().onEnded {
                                        viewModel.focusedPhotoIndex = index
                                        NSApp.keyWindow?.makeFirstResponder(nil)
                                    }
                                )
                                .simultaneousGesture(
                                    TapGesture(count: 2).onEnded {
                                        viewModel.focusedPhotoIndex = index
                                        viewModel.openLargeImageViewer()
                                        NSApp.keyWindow?.makeFirstResponder(nil)
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        NSApp.keyWindow?.makeFirstResponder(nil)
                    }
                }
                .onChange(of: viewModel.focusedPhotoIndex) { _, newIndex in
                    DispatchQueue.main.async {
                        if newIndex >= 0 && newIndex < viewModel.filteredPhotoSets.count {
                            let targetID = viewModel.filteredPhotoSets[newIndex].id
                            withAnimation(.easeInOut(duration: 0.15)) {
                                scrollProxy.scrollTo(targetID)
                            }
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
