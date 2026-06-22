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
                                    .background(Color.black)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            } else {
                                VStack {
                                    Spacer()
                                    Text("No photos to display")
                                        .foregroundStyle(PhotomatorTheme.textSecondary)
                                    Spacer()
                                }
                                .background(Color.black)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }

                            if viewModel.isInspectorOpen, let photo = viewModel.currentFocusedPhotoSet {
                                InspectorPanelView(metadata: viewModel.metadata(for: photo))
                                    .padding(12)
                                    .transition(.opacity.combined(with: .move(edge: .leading)))
                            }
                        }
                        .background(Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

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

            // Navigation counter
            Text("\(viewModel.focusedPhotoIndex + 1) / \(viewModel.filteredPhotoSets.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(PhotomatorTheme.textSecondary)

            // Photo name
            Text(photo.baseName)
                .font(.caption.weight(.medium))
                .foregroundStyle(PhotomatorTheme.textPrimary)
                .lineLimit(1)
                
            if photo.pick == 1 || photo.pick == -1 {
                Image(systemName: photo.pick == 1 ? "flag.fill" : "flag.slash.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(photo.pick == 1 ? .red : .orange)
            }
            
            if let rating = photo.rating, rating > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                    Text("\(rating)")
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(PhotomatorTheme.textPrimary)
            }

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
                        .foregroundStyle(PhotomatorTheme.textPrimary)
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
                        .foregroundStyle(photo.isSelected ? .green : PhotomatorTheme.textSecondary)
                    Text(photo.isSelected ? "Selected" : "Unselected")
                        .foregroundStyle(PhotomatorTheme.textPrimary)
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
                    .foregroundStyle(viewModel.isInspectorOpen ? Color.accentColor : PhotomatorTheme.textSecondary)
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
                    .foregroundStyle(PhotomatorTheme.textSecondary)
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
                .fill(PhotomatorTheme.background)
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
