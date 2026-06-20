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
            PhotomatorTheme.background
                .ignoresSafeArea()

            HStack(spacing: 0) {
                // Left Column (Top Bar + Image Canvas + Bottom Filmstrip)
                VStack(spacing: 0) {
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
                    .padding([.horizontal, .bottom], 12)
                    .padding(.top, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: viewModel.isInspectorOpen)
                }

                // Right Column (Sidebar controls & metadata)
                LargeImageViewerSidebar(viewModel: viewModel)
                    .ignoresSafeArea()
            }
            .ignoresSafeArea(edges: .top)
        }
    }

    // MARK: - Top bar

    @ViewBuilder
    private func topBar(_ photo: PhotoSet) -> some View {
        HStack(spacing: 12) {
            Spacer().frame(width: 72) // Space for macOS traffic lights

            // Back/Escape button next to traffic lights
            Button {
                viewModel.closeLargeImageViewer()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(6)
                    .liquidGlassButton(isHovered: false)
            }
            .buttonStyle(.plain)
            .help("Close viewer (Esc)")

            Rectangle()
                .fill(PhotomatorTheme.separator)
                .frame(width: 1, height: 16)

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
                        .foregroundStyle(photo.isSelected ? .green : .white.opacity(0.7))
                    Text(photo.isSelected ? "Selected" : "Unselected")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .liquidGlassButton(isHovered: false, isApplied: photo.isSelected, accentColor: .green)
            }
            .buttonStyle(.plain)
            .help("Toggle selection (S)")

            // Info toggle button
            Button {
                viewModel.isInspectorOpen.toggle()
            } label: {
                Image(systemName: "info.circle")
                    .font(.body)
                    .foregroundStyle(viewModel.isInspectorOpen ? Color.accentColor : Color.white.opacity(0.7))
                    .padding(6)
                    .liquidGlassButton(isHovered: false, isApplied: viewModel.isInspectorOpen)
            }
            .buttonStyle(.plain)
            .help("Toggle Metadata Inspector (I)")

            // Close button
            Button {
                viewModel.closeLargeImageViewer()
            } label: {
                Image(systemName: "xmark")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(6)
                    .liquidGlassButton(isHovered: false)
            }
            .buttonStyle(.plain)
            .help("Close viewer (Esc)")
        }
        .padding(.trailing, 12)
        .padding(.top, 10) // Matches ContentView's top padding for traffic lights
        .padding(.bottom, 8)
        .background(
            Rectangle()
                .fill(PhotomatorTheme.sidebarBackground)
                .ignoresSafeArea()
        )
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(PhotomatorTheme.separator),
            alignment: .bottom
        )
    }
}
