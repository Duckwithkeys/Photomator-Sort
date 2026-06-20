//
//  LargeImageViewer.swift
//  PhotomatorSort
//

import SwiftUI
import AppKit

// MARK: - Large Image Viewer (full-canvas overlay)

struct LargeImageViewer: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            HStack(spacing: 0) {
                // Left Column (Top Bar + Image Canvas + Bottom Filmstrip)
                VStack(spacing: 12) {
                    // Top bar: photo info + close
                    if let photo = viewModel.currentFocusedPhotoSet {
                        topBar(photo)
                    }

                    // Content Area (Canvas + Filmstrip)
                    VStack(spacing: 12) {
                        ZStack(alignment: .topLeading) {
                            if let photo = viewModel.currentFocusedPhotoSet {
                                LargeImagePane(photoSet: photo)
                            } else {
                                VStack {
                                    Spacer()
                                    Text("No photos to display")
                                        .foregroundStyle(.white.opacity(0.5))
                                    Spacer()
                                }
                            }

                            if viewModel.isInspectorOpen, let photo = viewModel.currentFocusedPhotoSet {
                                InspectorPanelView(metadata: viewModel.metadata(for: photo))
                                    .padding(12)
                                    .transition(.opacity.combined(with: .move(edge: .leading)))
                            }
                        }

                        FilmstripView(viewModel: viewModel)
                            .liquidGlassPanel()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: viewModel.isInspectorOpen)
                }
                .padding(.vertical, 12)
                .padding(.leading, 12)
                .padding(.trailing, 12)

                // Right Column (Sidebar controls & metadata)
                LargeImageViewerSidebar(viewModel: viewModel)
                    .ignoresSafeArea()
            }
        }
    }

    // MARK: - Top bar

    @ViewBuilder
    private func topBar(_ photo: PhotoSet) -> some View {
        HStack(spacing: 12) {
            // Navigation counter
            Text("\(viewModel.focusedPhotoIndex + 1) / \(viewModel.filteredPhotoSets.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.7))

            // Photo name
            Text(photo.baseName)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)

            Spacer()

            // Assigned tags
            let tags = viewModel.assignedTags(for: photo)
            if !tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(tags) { tag in
                        HStack(spacing: 3) {
                            Circle()
                                .fill(tag.color)
                                .frame(width: 6, height: 6)
                            Text(tag.name)
                                .font(.caption2)
                        }
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(tag.color.opacity(0.2), in: Capsule())
                    }
                }
            }

            Spacer()

            // Selection checkbox (checkmark button)
            Button {
                viewModel.toggleSelection(for: photo.id)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: photo.isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(photo.isSelected ? .green : .white.opacity(0.7))
                    Text(photo.isSelected ? "Selected" : "Unselected")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .help("Toggle selection (S)")

            // Info toggle button
            Button {
                viewModel.isInspectorOpen.toggle()
            } label: {
                Image(systemName: "info.circle")
                    .font(.title3)
                    .foregroundStyle(viewModel.isInspectorOpen ? .accentColor : .white.opacity(0.7))
                    .padding(8)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .help("Toggle Metadata Inspector (I)")

            // Close button
            Button {
                viewModel.closeLargeImageViewer()
            } label: {
                Image(systemName: "xmark")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(8)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .help("Close viewer (Esc)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .liquidGlassPanel()
    }
}
