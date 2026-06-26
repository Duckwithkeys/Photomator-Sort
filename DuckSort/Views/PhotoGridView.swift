//
//  PhotoGridView.swift
//  DuckSort
//
//  Grid of photo sets with selection, focus, shift-click range select,
//  and drag-to-select (marquee) when starting from empty space.
//

import SwiftUI
import AppKit

struct PhotoGridView: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel

    private static let minItemWidth: CGFloat = 180
    private static let gridSpacing: CGFloat = Theme.Space.s14
    private static let horizontalPadding: CGFloat = Theme.Space.s20

    @State private var cellFrames: [PhotoSet.ID: CGRect] = [:]
    @State private var gridOrigin: CGPoint = .zero
    @State private var marqueeStart: CGPoint? = nil
    @State private var marqueeCurrent: CGPoint? = nil

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
            ZStack(alignment: .topLeading) {
                // Layer 1: Empty-space hit area for marquee drag. Cells (above)
                // will absorb clicks first, so this gesture only ever fires
                // when the drag begins on a point not covered by any cell.
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 4, coordinateSpace: .named("PhotoGrid"))
                            .onChanged { value in
                                if marqueeStart == nil {
                                    if !isPointInAnyCell(value.startLocation) {
                                        marqueeStart = value.startLocation
                                    } else {
                                        return
                                    }
                                }
                                marqueeCurrent = value.location
                            }
                            .onEnded { value in
                                guard let start = marqueeStart else { return }
                                let end = marqueeCurrent ?? value.location
                                let rect = CGRect(
                                    x: min(start.x, end.x),
                                    y: min(start.y, end.y),
                                    width: abs(end.x - start.x),
                                    height: abs(end.y - start.y)
                                )
                                let hitIDs = cellFrames
                                    .filter { $0.value.intersects(rect) }
                                    .map { $0.key }
                                if !hitIDs.isEmpty {
                                    viewModel.replaceSelection(with: hitIDs)
                                    viewModel.selectionAnchorID = hitIDs.last
                                }
                                marqueeStart = nil
                                marqueeCurrent = nil
                            }
                    )

                // Layer 2: Cells. Layered above the marquee hit area so
                // normal clicks land on the cell's button first.
                ScrollView {
                    LazyVGrid(columns: columns, spacing: Self.gridSpacing) {
                        ForEach(Array(viewModel.filteredPhotoSets.enumerated()), id: \.element.id) { index, photoSet in
                            cell(for: index, photoSet: photoSet)
                                .id(photoSet.id)
                                .background(
                                    GeometryReader { proxy in
                                        Color.clear
                                            .preference(
                                                key: CellFramePreferenceKey.self,
                                                value: [CellFrame(id: photoSet.id, frame: proxy.frame(in: .named("PhotoGrid")))]
                                            )
                                    }
                                )
                        }
                    }
                    .padding(.horizontal, Self.horizontalPadding)
                    .padding(.top, Theme.Space.s16)
                    .padding(.bottom, Theme.Space.s16)
                    .background(
                        GeometryReader { proxy in
                            Color.clear
                                .onAppear {
                                    gridOrigin = proxy.frame(in: .named("PhotoGrid")).origin
                                }
                                .onChange(of: proxy.frame(in: .named("PhotoGrid")).origin) { _, newOrigin in
                                    gridOrigin = newOrigin
                                }
                        }
                    )
                }
                .coordinateSpace(name: "PhotoGrid")
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

                // Layer 3: Marquee rectangle overlay (visual only).
                if let start = marqueeStart, let current = marqueeCurrent {
                    let rect = CGRect(
                        x: min(start.x, current.x),
                        y: min(start.y, current.y),
                        width: abs(current.x - start.x),
                        height: abs(current.y - start.y)
                    )
                    Rectangle()
                        .stroke(Theme.Color.accent, lineWidth: 1)
                        .background(Rectangle().fill(Theme.Color.accent.opacity(0.12)))
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX - gridOrigin.x, y: rect.minY - gridOrigin.y)
                        .allowsHitTesting(false)
                }
            }
            .onPreferenceChange(CellFramePreferenceKey.self) { values in
                var updated = cellFrames
                for entry in values {
                    updated[entry.id] = entry.frame
                }
                cellFrames = updated
            }
        }
        .overlay(alignment: .top) {
            if viewModel.isScanning {
                ProgressView("Scanning subfolders...")
                    .padding(Theme.Space.s12)
                    .background(Theme.Color.cellBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.l))
                    .padding(.top, Theme.Space.s12)
            }
        }
    }

    private func isPointInAnyCell(_ point: CGPoint) -> Bool {
        cellFrames.values.contains { $0.contains(point) }
    }

    @ViewBuilder
    private func cell(for index: Int, photoSet: PhotoSet) -> some View {
        let isFocused = index == viewModel.focusedPhotoIndex
        EquatableView(content: PhotoSetCell(
            photoSet: photoSet,
            tags: viewModel.assignedTags(for: photoSet),
            isFocusedGridItem: isFocused,
            isJpegOnlyMode: viewModel.isJpegOnlyMode,
            handleClick: { click in
                viewModel.focusedPhotoIndex = index
                switch click {
                case .plain:
                    viewModel.toggleSelection(for: photoSet.id)
                case .shiftClick:
                    viewModel.selectRange(to: photoSet.id, additive: false)
                case .commandClick:
                    viewModel.toggleSelection(for: photoSet.id)
                }
            },
            openInViewer: {
                viewModel.focusedPhotoIndex = index
                viewModel.openLargeImageViewer()
            }
        ))
    }
}

private struct CellFrame: Equatable {
    let id: PhotoSet.ID
    let frame: CGRect
}

private struct CellFramePreferenceKey: PreferenceKey {
    static var defaultValue: [CellFrame] = []
    static func reduce(value: inout [CellFrame], nextValue: () -> [CellFrame]) {
        value.append(contentsOf: nextValue())
    }
}