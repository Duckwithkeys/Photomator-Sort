//
//  PhotoSetCell.swift
//  DuckSort
//
//  One tile in the photo grid. Single tap → toggle selection.
//  Double tap → open in large image viewer.
//
//  Modifier flags for click handling are read directly from
//  `NSEvent.modifierFlags` because SwiftUI on macOS does not expose
//  modifier-aware single-tap gestures.
//

import SwiftUI
import AppKit

struct PhotoSetCell: View, Equatable {
    let photoSet: PhotoSet
    let tags: [CustomTag]
    let isFocusedGridItem: Bool
    let isJpegOnlyMode: Bool
    let handleClick: (MouseClick) -> Void
    let openInViewer: () -> Void
    @State private var isHovered = false

    /// SwiftUI calls this when deciding whether to re-render. Comparing only
    /// the inputs (not internal @State) means ~99 unchanged cells in the
    /// grid skip body evaluation when only one cell's selection flips.
    static func == (lhs: PhotoSetCell, rhs: PhotoSetCell) -> Bool {
        lhs.photoSet == rhs.photoSet &&
        lhs.tags == rhs.tags &&
        lhs.isFocusedGridItem == rhs.isFocusedGridItem &&
        lhs.isJpegOnlyMode == rhs.isJpegOnlyMode
    }

    enum MouseClick {
        case plain         // single-click toggle
        case shiftClick    // shift-click range select
        case commandClick  // cmd-click additive toggle
    }

    private var selectionBorderColor: Color {
        photoSet.isSelected ? Theme.Color.success : Color.clear
    }

    private var focusBorderColor: Color {
        isFocusedGridItem ? Theme.Color.accent : Color.clear
    }

    private var isRejected: Bool { photoSet.pick == -1 }

    private var formatBadgeStatus: FormatBadge.Status {
        // Always show the edited badge when the .photo-edit file is present,
        // regardless of mode — the wand is the universal signal that this
        // set has non-destructive edits applied.
        if photoSet.hasEdit { return .edited }
        return .normal
    }

    var body: some View {
        Button {
            // Read modifier flags directly via NSEvent.modifierFlags rather
            // than NSApp.currentEvent?.modifierFlags — the latter can lag a
            // tick behind a click and lose the shift/cmd flag.
            let flags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let click: MouseClick
            if flags.contains(.shift) {
                click = .shiftClick
            } else if flags.contains(.command) {
                click = .commandClick
            } else {
                click = .plain
            }
            handleClick(click)
        } label: {
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
                    }
                    .padding(Theme.Space.s8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                    if let rating = photoSet.rating, rating > 0 {
                        RatingBadge(rating: rating)
                            .padding(Theme.Space.s8)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    }
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
        .contextMenu {
            Button("Reveal in Finder") {
                if let url = photoSet.preferredPreviewURL {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
        }
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

            // Always reserve a single line of vertical space for tag pills so
            // adding/removing tags doesn't shift the cell's metadata text or
            // change the position of the rating badge on the thumbnail.
            tagPillsArea
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A single-line tag pill area. Always renders with a fixed height so the
    /// cell layout stays stable whether or not the photo has tags. Long tag
    /// lists are truncated with a "+N" overflow indicator.
    @ViewBuilder
    private var tagPillsArea: some View {
        HStack(spacing: Theme.Space.s4) {
            if tags.isEmpty {
                Color.clear
            } else {
                ForEach(Array(tags.prefix(2))) { tag in
                    tagPill(tag)
                }
                if tags.count > 2 {
                    tagPillOverflow(extra: tags.count - 2)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: 22)
        .lineLimit(1)
    }

    private func tagPill(_ tag: CustomTag) -> some View {
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

    private func tagPillOverflow(extra: Int) -> some View {
        Text("+\(extra)")
            .font(Theme.Font.caption2)
            .foregroundStyle(Theme.Color.textSecondary)
            .padding(.horizontal, Theme.Space.s4)
            .frame(height: 22)
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

    /// Background tint of the pill. Multi-format sets take the colour of
    /// their readable derivative (JPEG → green, HEIF → indigo) so the
    /// user can see at a glance whether the set is JPEG-backed or HEIF-backed.
    /// Pure RAW sets use red. The colours are shared with the large
    /// viewer's file list so both surfaces agree.
    private var pillBackground: Color {
        let upper = label.uppercased()
        if upper.contains("JPEG") { return Theme.Color.FileColor.jpeg }
        if upper.contains("HEIF") { return Theme.Color.FileColor.heif }
        if upper.contains("RAW")  { return Theme.Color.FileColor.raw }
        return Theme.Color.FileColor.other
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(pillBackground, in: Capsule())
                .overlay(
                    Capsule().stroke(.white.opacity(0.55), lineWidth: Theme.Stroke.hairline)
                )

            switch status {
            case .normal:
                EmptyView()
            case .edited:
                Image(systemName: "wand.and.stars")
                    .font(Theme.Font.badge)
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Theme.Color.warning, in: Circle())
                    .overlay(
                        Circle().stroke(.white.opacity(0.4), lineWidth: Theme.Stroke.hairline)
                    )
            case .incomplete:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(Theme.Font.badge)
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Theme.Color.danger, in: Circle())
                    .overlay(
                        Circle().stroke(.white.opacity(0.4), lineWidth: Theme.Stroke.hairline)
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