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
    @State private var isHovered = false



    var body: some View {
        Button(action: toggleSelection) {
            VStack(alignment: .leading, spacing: 6) {
                ThumbnailView(url: photoSet.preferredPreviewURL)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .grayscale(photoSet.pick == -1 ? 0.8 : 0)
                    .opacity(photoSet.pick == -1 ? 0.6 : 1.0)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                photoSet.isSelected ? Color.green : (isHovered ? Color.white.opacity(0.15) : Color.clear),
                                lineWidth: photoSet.isSelected ? 3 : 1
                            )
                    )
                    .overlay {
                        if isFocusedGridItem {
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(PhotomatorTheme.selectedBlue, lineWidth: 2.5)
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        // Format Badge & Wand/Warning Icon on Top-Left (Wand = edited in orange; Exclamation = needs edit in red)
                        HStack(spacing: 4) {
                            Text(photoSet.formatLabel)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.white, in: RoundedRectangle(cornerRadius: 4))
                            
                            let formats = photoSet.mediaFormats
                            let isComplete = formats.isRaw && formats.isHeif && photoSet.hasEdit
                            let showWand = isJpegOnlyMode ? photoSet.hasEdit : isComplete
                            let showWarning = !isJpegOnlyMode && !isComplete
                            
                            if showWand {
                                Image(systemName: "wand.and.stars")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 16, height: 16)
                                    .background(Color.orange, in: Circle())
                            } else if showWarning {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 16, height: 16)
                                    .background(Color.red, in: Circle())
                            }
                        }
                        .padding(8)
                    }
                    .overlay(alignment: .bottomLeading) {
                        // Rating Badge on Bottom-Left
                        if let rating = photoSet.rating, rating > 0 {
                            HStack(spacing: 2) {
                                Text("\(rating)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                                Image(systemName: "star.fill")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.black.opacity(0.6), in: Capsule())
                            .padding(8)
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        // Flag Badge on Bottom-Right
                        if let pick = photoSet.pick, pick == 1 || pick == -1 {
                            Image(systemName: pick == 1 ? "flag.fill" : "flag.slash.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(pick == 1 ? .red : .orange)
                                .padding(5)
                                .background(.black.opacity(0.6), in: Circle())
                                .padding(8)
                        }
                    }

                // Text below thumbnail, centered
                VStack(spacing: 2) {
                    Text(photoSet.baseName)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(photoSet.isSelected ? Color.green : (isFocusedGridItem ? PhotomatorTheme.selectedBlue : PhotomatorTheme.textPrimary))
                        .lineLimit(1)

                    Text("\(photoSet.mediaCount) media\(photoSet.hasEdit ? " + edit" : "")")
                        .font(.caption)
                        .foregroundStyle(PhotomatorTheme.textSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 4)

                if !tags.isEmpty {
                    tagPills
                        .frame(maxWidth: .infinity)
                }
                
                Spacer(minLength: 0)
            }
            .padding(4)
            .frame(maxHeight: .infinity, alignment: .top)
            .onHover { isHovered in
                self.isHovered = isHovered
                if isHovered {
                    LargeImageLoader.preload(url: photoSet.preferredPreviewURL)
                }
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
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
