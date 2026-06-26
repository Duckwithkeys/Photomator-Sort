//
//  LargeImageViewer.swift
//  DuckSort
//

import SwiftUI
import AppKit

struct LargeImageViewer: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel

    var body: some View {
        ZStack(alignment: .top) {
            Theme.Color.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar spans the full width so the right sidebar's column
                // doesn't show a different color above it.
                if let photo = viewModel.currentFocusedPhotoSet {
                    topBar(photo)
                }

                HStack(spacing: 0) {
                    if viewModel.isInspectorOpen {
                        InspectorPanelView(metadata: currentMetadata)
                            .frame(width: 280)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }

                    VStack(spacing: 0) {
                        imagePane
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(Theme.Space.s12)

                        FilmstripView(viewModel: viewModel)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    LargeImageViewerSidebar(viewModel: viewModel)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.Color.background)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: viewModel.isInspectorOpen)
        }
    }

    @ViewBuilder
    private var imagePane: some View {
        if let photo = viewModel.currentFocusedPhotoSet {
            LargeImagePane(photoSet: photo)
                .background(Theme.Color.scrim, in: RoundedRectangle(cornerRadius: Theme.Radius.xl))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xl))
        } else {
            VStack {
                Spacer()
                Text("No photos to display")
                    .foregroundStyle(Theme.Color.textSecondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.Color.scrim, in: RoundedRectangle(cornerRadius: Theme.Radius.xl))
        }
    }

    private var currentMetadata: MetadataSnapshot {
        guard let photo = viewModel.currentFocusedPhotoSet else {
            return MetadataSnapshot(cameraModel: nil, lensModel: nil, captureDate: nil,
                                    aperture: nil, shutterSpeed: nil, iso: nil)
        }
        return viewModel.metadata(for: photo)
    }

    @ViewBuilder
    private func topBar(_ photo: PhotoSet) -> some View {
        HStack(spacing: Theme.Space.s12) {
            // Leading: counter + name + indicators
            HStack(spacing: Theme.Space.s8) {
                Text("\(viewModel.focusedPhotoIndex + 1) / \(viewModel.filteredPhotoSets.count)")
                    .font(Theme.Font.monoCaption)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .layoutPriority(2)

                Text(photo.baseName)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Color.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(1)

                HStack(spacing: Theme.Space.s4) {
                    if let rating = photo.rating, rating > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill")
                                .foregroundStyle(Theme.Color.rating)
                            Text("\(rating)")
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Color.textPrimary)
                        }
                    }
                    if photo.pick == 1 || photo.pick == -1 {
                        Image(systemName: photo.pick == 1 ? "flag.fill" : "flag.slash.fill")
                            .font(Theme.Font.caption)
                            .foregroundStyle(photo.pick == 1 ? Theme.Color.danger : Theme.Color.warning)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Trailing: actions
            HStack(spacing: Theme.Space.s8) {
                selectionButton(photo)
                inspectorButton
                closeButton
            }
        }
        .padding(.horizontal, Theme.Space.s12)
        .frame(height: 44)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Color.background)
        .overlay(Divider(), alignment: .bottom)
    }

    private func selectionButton(_ photo: PhotoSet) -> some View {
        Button {
            viewModel.toggleSelection(for: photo.id)
        } label: {
            HStack(spacing: Theme.Space.s6) {
                Image(systemName: photo.isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(photo.isSelected ? Theme.Color.success : Theme.Color.textSecondary)
                Text(photo.isSelected ? "Selected" : "Select")
                    .foregroundStyle(Theme.Color.textPrimary)
                    .font(Theme.Font.caption)
            }
            .padding(.horizontal, Theme.Space.s10)
            .padding(.vertical, Theme.Space.s4)
            .liquidGlassButton(isApplied: photo.isSelected, accentColor: Theme.Color.success)
        }
        .buttonStyle(.plain)
        .help("Toggle selection (S)")
    }

    private var inspectorButton: some View {
        Button {
            viewModel.isInspectorOpen.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.body)
                .foregroundStyle(viewModel.isInspectorOpen ? Theme.Color.accent : Theme.Color.textSecondary)
                .padding(Theme.Space.s6)
                .liquidGlassButton(isApplied: viewModel.isInspectorOpen)
        }
        .buttonStyle(.plain)
        .help("Toggle Metadata Inspector (I)")
    }

    private var closeButton: some View {
        Button {
            viewModel.closeLargeImageViewer()
        } label: {
            Image(systemName: "xmark")
                .font(.body)
                .foregroundStyle(Theme.Color.textSecondary)
                .padding(Theme.Space.s6)
                .liquidGlassButton()
        }
        .buttonStyle(.plain)
        .help("Close viewer (Esc)")
    }
}
