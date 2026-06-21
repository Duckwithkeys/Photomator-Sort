//
//  PhotoSetCell.swift
//  PhotomatorSort
//

import SwiftUI

struct PhotoSetCell: View {
    let photoSet: PhotoSet
    let tags: [CustomTag]
    let isFocusedGridItem: Bool
    let isJpegOnlyMode: Bool
    let toggleSelection: () -> Void
    let openBigView: () -> Void
    @State private var isHovered = false

    private var statusColor: Color {
        if photoSet.isSelected { return PhotomatorTheme.selectedBlue }
        if isJpegOnlyMode { return PhotomatorTheme.selectedBlue }
        if !photoSet.hasEdit { return .red }
        return .orange
    }

    private var statusBackground: Color {
        statusColor.opacity(photoSet.isSelected ? 0.20 : 0.10)
    }

    var body: some View {
        Button(action: toggleSelection) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    ThumbnailView(url: photoSet.preferredPreviewURL)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .grayscale(photoSet.pick == -1 ? 0.8 : 0)
                        .opacity(photoSet.pick == -1 ? 0.6 : 1.0)

                    statusBadge

                    if photoSet.pick == 1 || photoSet.pick == -1 {
                        Image(systemName: photoSet.pick == 1 ? "flag.fill" : "flag.slash.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(photoSet.pick == 1 ? .white : .red)
                            .padding(6)
                            .background(.black.opacity(0.5), in: Circle())
                            .padding(8)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                    
                    if let rating = photoSet.rating, rating > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.yellow)
                            Text("\(rating)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.5), in: Capsule())
                        .padding(8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    }

                    if isHovered {
                        Image(systemName: "info.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(.ultraThinMaterial, in: Circle())
                            .shadow(color: .black.opacity(0.2), radius: 2)
                            .highPriorityGesture(
                                TapGesture().onEnded {
                                    openBigView()
                                }
                            )
                            .transition(.opacity.combined(with: .scale))
                            .padding(8)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .help("Open large image viewer")
                    }
                }

                HStack(spacing: 8) {
                    Image(systemName: photoSet.isSelected ? "checkmark.circle.fill" : "circle.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(statusColor)
                        .frame(width: 24, height: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(photoSet.baseName)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)

                        Text("\(photoSet.mediaCount) media\(photoSet.hasEdit ? " + edit" : "")")
                            .font(.caption)
                            .foregroundStyle(photoSet.hasEdit ? Color.secondary : Color.red)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !tags.isEmpty {
                    tagPills
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .liquidGlassButton(isHovered: isHovered, isApplied: photoSet.isSelected, accentColor: statusColor)
            .overlay {
                if isFocusedGridItem {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.accentColor, lineWidth: 2)
                        .padding(-2)
                }
            }
            .onHover { isHovered in
                self.isHovered = isHovered
                if isHovered {
                    LargeImageLoader.preload(url: photoSet.preferredPreviewURL)
                }
            }
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private var statusBadge: some View {
        if !isJpegOnlyMode {
            Label(
                photoSet.hasEdit ? "Edited" : "Needs edit",
                systemImage: photoSet.hasEdit ? "wand.and.stars" : "exclamationmark.triangle.fill"
            )
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .labelStyle(.iconOnly)
            .padding(5)
            .background(statusColor, in: Circle())
            .padding(5)
            .help(photoSet.hasEdit ? "Photomator edit detected" : "No Photomator edit sidecar found")
        }
    }

    private var tagPills: some View {
        HStack(spacing: 4) {
            ForEach(tags) { tag in
                HStack(spacing: 3) {
                    Circle()
                        .fill(tag.color)
                        .frame(width: 7, height: 7)
                    Text(tag.name)
                        .font(.caption2.weight(.medium))
                        .lineLimit(1)
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(tag.color.opacity(0.20), in: Capsule())
            }
        }
    }
}
