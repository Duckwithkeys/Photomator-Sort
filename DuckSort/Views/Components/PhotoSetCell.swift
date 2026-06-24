//
//  PhotoSetCell.swift
//  DuckSort
//
//  One tile in the photo grid. Single tap → toggle selection.
//  Double tap → open in large image viewer.
//

import SwiftUI

struct PhotoSetCell: View {
    let photoSet: PhotoSet
    let tags: [CustomTag]
    let isFocusedGridItem: Bool
    let isJpegOnlyMode: Bool
    let toggleSelection: () -> Void
    let openInViewer: () -> Void
    @State private var isHovered = false

    private var selectionBorderColor: Color {
        photoSet.isSelected ? Theme.Color.success : Color.clear
    }

    private var focusBorderColor: Color {
        isFocusedGridItem ? Theme.Color.accent : Color.clear
    }

    private var isRejected: Bool { photoSet.pick == -1 }

    private var formatBadgeStatus: FormatBadge.Status {
        if isJpegOnlyMode {
            return photoSet.hasEdit ? .edited : .normal
        }
        let formats = photoSet.mediaFormats
        let hasDerivative = formats.isHeif || formats.isJpeg
        // A set is "edited" when RAW + derivative + .photo-edit are all present.
        if formats.isRaw && hasDerivative && photoSet.hasEdit { return .edited }
        return .normal
    }

    var body: some View {
        Button(action: toggleSelection) {
            VStack(alignment: .leading, spacing: Theme.Space.s6) {
                // ZStack so the focus ring can draw *outside* the thumbnail's
                // rounded corners without overlapping the selection ring.
                ZStack(alignment: .topLeading) {
                    thumbnail
                        .overlay(alignment: .topLeading) {
                            // Empty — the badges are placed inside the ZStack
                            // below so they're not subject to the thumbnail's
                            // clipShape, which can drop them in some
                            // LazyVGrid layouts.
                            Color.clear
                        }
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xl))

                    VStack(alignment: .leading, spacing: Theme.Space.s4) {
                        HStack(alignment: .top, spacing: Theme.Space.s4) {
                            FormatBadge(status: formatBadgeStatus, label: photoSet.formatLabel)
                            Spacer(minLength: 0)
                            if let pick = photoSet.pick, pick == 1 || pick == -1 {
                                Image(systemName: pick == 1 ? "flag.fill" : "flag.slash.fill")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(Theme.Color.textInverse)
                                    .frame(width: 22, height: 22)
                                    .background(pick == 1 ? Theme.Color.danger : Theme.Color.warning, in: Circle())
                                    .overlay(Circle().stroke(.white.opacity(0.3), lineWidth: 1))
                            }
                        }
                        Spacer(minLength: 0)
                        if let rating = photoSet.rating, rating > 0 {
                            RatingBadge(rating: rating)
                        }
                    }
                    .padding(Theme.Space.s8)
                }
                // Selection ring (green) — drawn on the thumbnail itself.
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.xl)
                        .strokeBorder(photoSet.isSelected ? Theme.Color.success : Color.clear, lineWidth: 4)
                )
                // Focus ring (blue) — drawn just outside the thumbnail's
                // selection ring so both colors are visible at once.
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.xl + 5)
                        .strokeBorder(isFocusedGridItem ? Theme.Color.accent : Color.clear, lineWidth: 3)
                        .padding(-5)
                )

                metadataBar
            }
            .padding(Theme.Space.s4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .shadow(color: isHovered ? Theme.Color.overlayScrim : .clear, radius: isHovered ? 6 : 0)
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                LargeImageLoader.preload(url: photoSet.preferredPreviewURL)
            }
        }
        .onTapGesture(count: 2) { openInViewer() }
    }

    private var thumbnail: some View {
        ThumbnailView(url: photoSet.preferredPreviewURL)
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .saturation(isRejected ? 0 : 1)
            .opacity(isRejected ? 0.55 : 1.0)
    }

    private var metadataBar: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s2) {
            Text(photoSet.baseName)
                .font(Theme.Font.callout)
                .foregroundStyle(photoSet.isSelected ? Theme.Color.success
                                : (isFocusedGridItem ? Theme.Color.accent : Theme.Color.textPrimary))
                .lineLimit(1)

            HStack(spacing: Theme.Space.s6) {
                Text("\(photoSet.mediaCount) media\(photoSet.hasEdit ? " + edit" : "")")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.textSecondary)

                Spacer(minLength: 0)
            }
            .lineLimit(1)

            if !tags.isEmpty {
                tagPills
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var tagPills: some View {
        HStack(spacing: Theme.Space.s4) {
            ForEach(tags) { tag in
                HStack(spacing: Theme.Space.s4) {
                    Circle()
                        .fill(tag.color)
                        .frame(width: 7, height: 7)
                    Text(tag.name)
                        .font(Theme.Font.caption2)
                        .lineLimit(1)
                }
                .padding(.horizontal, Theme.Space.s4)
                .padding(.vertical, Theme.Space.s2)
                .background(tag.color.opacity(0.20), in: Capsule())
            }
        }
    }
}

// MARK: - Format Badge

private struct FormatBadge: View {
    enum Status {
        case normal, edited, incomplete
    }
    let status: Status
    let label: String

    var body: some View {
        HStack(spacing: Theme.Space.s4) {
            // High-contrast pill so the format is readable on any photo.
            Text(label)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.Color.textInverse)
                .padding(.horizontal, Theme.Space.s8)
                .padding(.vertical, Theme.Space.s4)
                .background(
                    Theme.Color.background.opacity(0.92),
                    in: RoundedRectangle(cornerRadius: Theme.Radius.s)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.s)
                        .stroke(Theme.Color.textInverse.opacity(0.15), lineWidth: Theme.Stroke.hairline)
                )

            switch status {
            case .normal:
                EmptyView()
            case .edited:
                Image(systemName: "wand.and.stars")
                    .font(Theme.Font.badge)
                    .foregroundStyle(Theme.Color.textPrimary)
                    .frame(width: 22, height: 22)
                    .background(Theme.Color.rating, in: Circle())
                    .overlay(
                        Circle().stroke(Theme.Color.textInverse.opacity(0.2), lineWidth: Theme.Stroke.hairline)
                    )
            case .incomplete:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(Theme.Font.badge)
                    .foregroundStyle(Theme.Color.textInverse)
                    .frame(width: 22, height: 22)
                    .background(Theme.Color.danger, in: Circle())
                    .overlay(
                        Circle().stroke(Theme.Color.textInverse.opacity(0.2), lineWidth: Theme.Stroke.hairline)
                    )
            }
        }
    }
}

// MARK: - Rating Badge

private struct RatingBadge: View {
    let rating: Int

    var body: some View {
        HStack(spacing: 2) {
            Text("\(rating)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.Color.textPrimary)
            Image(systemName: "star.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.Color.textPrimary)
        }
        .padding(.horizontal, Theme.Space.s8)
        .padding(.vertical, Theme.Space.s4)
        .background(Theme.Color.rating, in: Capsule())
        .overlay(
            Capsule().stroke(Theme.Color.textInverse.opacity(0.25), lineWidth: Theme.Stroke.hairline)
        )
    }
}
