//
//  PhotoGridView.swift
//  DuckSort
//

import SwiftUI

struct PhotoGridView: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel

    private static let minItemWidth: CGFloat = 180
    private static let gridSpacing: CGFloat = Theme.Space.s14
    private static let horizontalPadding: CGFloat = Theme.Space.s20

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
        return max(1, Int(floor(val)))
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: Self.gridSpacing) {
                    ForEach(Array(viewModel.filteredPhotoSets.enumerated()), id: \.element.id) { index, photoSet in
                        cell(for: index, photoSet: photoSet)
                            .id(photoSet.id)
                    }
                }
                .padding(.horizontal, Self.horizontalPadding)
                .padding(.bottom, Theme.Space.s16)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                GridHeader(
                    filterRule: viewModel.filterRule,
                    count: viewModel.filteredPhotoSets.count
                )
            }
            .background(GeometryReader { geometry in
                Color.clear.onAppear {
                    viewModel.gridColumnCount = Self.columnCount(forWidth: geometry.size.width)
                }
                .onChange(of: geometry.size.width) { _, newWidth in
                    viewModel.gridColumnCount = Self.columnCount(forWidth: newWidth)
                }
            })
            .onChange(of: viewModel.focusedPhotoIndex) { _, newIndex in
                if newIndex >= 0 && newIndex < viewModel.filteredPhotoSets.count {
                    let targetID = viewModel.filteredPhotoSets[newIndex].id
                    scrollProxy.scrollTo(targetID)
                }
            }
        }
        .overlay(alignment: .top) {
            if viewModel.isScanning {
                ProgressView("Scanning subfolders...")
                    .padding(Theme.Space.s12)
                    .background(Theme.Color.cellBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.l))
                    .padding(.top, Theme.Space.s44)
            }
        }
    }

    @ViewBuilder
    private func cell(for index: Int, photoSet: PhotoSet) -> some View {
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
            openInViewer: {
                viewModel.focusedPhotoIndex = index
                viewModel.openLargeImageViewer()
            }
        )
    }
}

// MARK: - Grid Header

private struct GridHeader: View {
    let filterRule: PhotoFilterRule
    let count: Int

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s8) {
                Text(filterRule.rawValue)
                    .font(Theme.Font.headline)
                    .foregroundStyle(Theme.Color.textPrimary)

                Text("^[\(count) photo set](inflect: true)")
                    .font(Theme.Font.footnote)
                    .foregroundStyle(Theme.Color.textSecondary)

                Spacer()
            }
            .padding(.horizontal, Theme.Space.s20)
            .padding(.top, Theme.Space.s12)
            .padding(.bottom, Theme.Space.s10)

            Divider()
        }
        .background(Theme.Color.background)
    }
}
