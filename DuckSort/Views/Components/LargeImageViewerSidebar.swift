//
//  LargeImageViewerSidebar.swift
//  DuckSort
//

import SwiftUI

struct LargeImageViewerSidebar: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel
    @ObservedObject private var preferences = UserPreferences.shared

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.s20) {

                    // Section 1: Tags
                    VStack(alignment: .leading, spacing: Theme.Space.s10) {
                        sectionHeader("ACTIVE TAGS")

                        if let photo = viewModel.currentFocusedPhotoSet {
                            let assignedTags = viewModel.assignedTags(for: photo)

                            if assignedTags.isEmpty {
                                Text("No tags applied")
                                    .font(Theme.Font.caption)
                                    .foregroundStyle(Theme.Color.textSecondary)
                            } else {
                                VStack(alignment: .leading, spacing: Theme.Space.s6) {
                                    ForEach(assignedTags) { tag in
                                        HStack(spacing: Theme.Space.s6) {
                                            Circle()
                                                .fill(tag.color)
                                                .frame(width: 8, height: 8)
                                            Text(tag.name)
                                                .font(Theme.Font.caption)
                                                .foregroundStyle(Theme.Color.textPrimary)
                                            Spacer()
                                            Button {
                                                viewModel.removeTag(tag, from: photo.id)
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .font(Theme.Font.caption2)
                                                    .foregroundStyle(Theme.Color.textSecondary)
                                            }
                                            .buttonStyle(.plain)
                                            .help("Remove tag")
                                        }
                                        .padding(.horizontal, Theme.Space.s8)
                                        .padding(.vertical, Theme.Space.s4)
                                        .background(tag.color.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.m))
                                    }
                                }
                            }
                        } else {
                            Text("No photo selected")
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Color.textSecondary)
                        }
                    }

                    Divider()

                    // Section 2: Metadata
                    VStack(alignment: .leading, spacing: Theme.Space.s12) {
                        sectionHeader("IMAGE METADATA")

                        if let photo = viewModel.currentFocusedPhotoSet {
                            let meta = viewModel.metadata(for: photo)

                            VStack(alignment: .leading, spacing: Theme.Space.s10) {
                                metadataField(label: "Filename", value: photo.baseName, systemImage: "photo")
                                filesInSet(photo)
                                metadataField(label: "Captured", value: meta.captureDate.map(formatDate) ?? "—", systemImage: "calendar")
                                metadataField(label: "Camera",   value: meta.cameraModel ?? "—", systemImage: "camera")
                                metadataField(label: "Lens",     value: meta.lensModel ?? "—", systemImage: "camera.macro")
                            }
                        } else {
                            Text("No photo selected")
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Color.textSecondary)
                        }
                    }

                    Divider()

                    // Section 2.5: Caption / Description
                    if let photo = viewModel.currentFocusedPhotoSet {
                        CaptionEditorView(viewModel: viewModel, photoSet: photo)
                    }

                    Divider()

                    // Section 3: Advanced EXIF (toggle-gated by menu bar)
                    if preferences.showAdvancedEXIF {
                        VStack(alignment: .leading, spacing: Theme.Space.s12) {
                            sectionHeader("ADVANCED EXIF")

                            if let photo = viewModel.currentFocusedPhotoSet {
                                let meta = viewModel.metadata(for: photo)

                                VStack(alignment: .leading, spacing: Theme.Space.s10) {
                                    metadataField(
                                        label: "Focal Length",
                                        value: formatFocalLength(meta.focalLength, equivalent35mm: meta.focalLengthIn35mm),
                                        systemImage: "viewfinder"
                                    )
                                    metadataField(
                                        label: "White Balance",
                                        value: meta.whiteBalance ?? "—",
                                        systemImage: "thermometer.sun"
                                    )
                                    metadataField(
                                        label: "Flash",
                                        value: formatFlash(fired: meta.flashFired, mode: meta.flashMode),
                                        systemImage: "bolt.fill"
                                    )
                                    metadataField(
                                        label: "Exposure Program",
                                        value: meta.exposureProgram ?? "—",
                                        systemImage: "slider.horizontal.3"
                                    )
                                    metadataField(
                                        label: "Metering Mode",
                                        value: meta.meteringMode ?? "—",
                                        systemImage: "scope"
                                    )
                                    metadataField(
                                        label: "Exposure Bias",
                                        value: formatExposureBias(meta.exposureBias),
                                        systemImage: "plus.forwardslash.minus"
                                    )
                                    metadataField(
                                        label: "Dimensions",
                                        value: formatDimensions(width: meta.pixelWidth, height: meta.pixelHeight),
                                        systemImage: "ruler"
                                    )
                                    metadataField(
                                        label: "Color Space",
                                        value: meta.colorSpace ?? "—",
                                        systemImage: "paintpalette"
                                    )
                                    metadataField(
                                        label: "Color Profile",
                                        value: meta.colorProfile ?? "—",
                                        systemImage: "swatchpalette"
                                    )
                                    metadataField(
                                        label: "Orientation",
                                        value: formatOrientation(meta.orientation),
                                        systemImage: "rotate.right"
                                    )
                                    metadataField(
                                        label: "GPS Coordinates",
                                        value: formatGPS(latitude: meta.gpsLatitude, longitude: meta.gpsLongitude),
                                        systemImage: "location"
                                    )
                                    metadataField(
                                        label: "GPS Altitude",
                                        value: formatAltitude(meta.gpsAltitude),
                                        systemImage: "mountain.2"
                                    )
                                }
                            } else {
                                Text("No photo selected")
                                    .font(Theme.Font.caption)
                                    .foregroundStyle(Theme.Color.textSecondary)
                            }
                        }

                        Divider()
                    }

                    // Section 4: Export Preview
                    VStack(alignment: .leading, spacing: Theme.Space.s10) {
                        sectionHeader("ROUTED EXPORT PREVIEW")

                        if let photo = viewModel.currentFocusedPhotoSet {
                            let meta = viewModel.metadata(for: photo)
                            let tags = viewModel.assignedTags(for: photo)

                            VStack(alignment: .leading, spacing: Theme.Space.s8) {
                                if let rule = viewModel.ruleStore.selectedRule {
                                    VStack(alignment: .leading, spacing: Theme.Space.s4) {
                                        Text("Active Rule")
                                            .font(Theme.Font.caption)
                                            .foregroundStyle(Theme.Color.textSecondary)
                                        Text(rule.name)
                                            .font(Theme.Font.caption)
                                    }

                                    if let dest = viewModel.destinationDirectory {
                                        let folders = ExportPathRouter.destinationFolders(
                                            base: dest,
                                            rule: rule.components,
                                            metadata: meta,
                                            assignedTags: tags
                                        ) {
                                            viewModel.tagStore.categoryName(id: $0)
                                        }

                                        VStack(alignment: .leading, spacing: Theme.Space.s4) {
                                            Text(folders.count <= 1 ? "Folder Destination" : "Folder Destinations")
                                                .font(Theme.Font.caption)
                                                .foregroundStyle(Theme.Color.textSecondary)
                                            ForEach(folders, id: \.self) { folder in
                                                Text(folder.path)
                                                    .font(Theme.Font.monoBody)
                                                    .foregroundStyle(Theme.Color.textSecondary)
                                                    .lineLimit(2)
                                                    .truncationMode(.middle)
                                            }
                                        }
                                    }
                                } else {
                                    Text("No rule selected")
                                        .font(Theme.Font.caption)
                                        .foregroundStyle(Theme.Color.warning)
                                }
                            }
                            .padding(Theme.Space.s10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.Color.cellBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.m))
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.Radius.m)
                                    .stroke(Theme.Color.separator, lineWidth: Theme.Stroke.hairline)
                            )
                        }
                    }
                }
                .padding(Theme.Space.s14)
            }
        }
        .frame(width: 260)
        .background(Theme.Color.sidebarBackground)
        .overlay(Divider(), alignment: .leading)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(Theme.Font.subheadline)
            .foregroundStyle(Theme.Color.textSecondary)
    }

    private func metadataField(label: String, value: String, systemImage: String, iconColor: Color = Theme.Color.textSecondary) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.s8) {
            Image(systemName: systemImage)
                .font(Theme.Font.caption)
                .foregroundStyle(iconColor)
                .frame(width: 14, alignment: .center)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(Theme.Font.caption2)
                    .foregroundStyle(Theme.Color.textSecondary)
                Text(value)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Replaces the old "N files + edit" summary with a real file list.
    /// Each row shows the actual filename (e.g. "DSCF0142.RAW") and a
    /// colour-coded chip describing its role. Right-click reveals the
    /// file in Finder.
    @ViewBuilder
    private func filesInSet(_ photo: PhotoSet) -> some View {
        let breakdown = photo.fileBreakdown
        VStack(alignment: .leading, spacing: Theme.Space.s6) {
            HStack(spacing: Theme.Space.s6) {
                Image(systemName: photo.hasEdit ? "wand.and.stars" : "link")
                    .font(Theme.Font.caption)
                    .foregroundStyle(photo.hasEdit ? Theme.Color.warning : Theme.Color.textSecondary)
                    .frame(width: 14, alignment: .center)
                Text("Files in Set")
                    .font(Theme.Font.caption2)
                    .foregroundStyle(Theme.Color.textSecondary)
                Spacer(minLength: 0)
                Text("\(breakdown.count) file\(breakdown.count == 1 ? "" : "s")")
                    .font(Theme.Font.caption2)
                    .foregroundStyle(Theme.Color.textTertiary)
            }

            VStack(alignment: .leading, spacing: Theme.Space.s4) {
                ForEach(breakdown) { entry in
                    FileListRow(entry: entry)
                }
            }
            .padding(.leading, 22) // align with metadata values below the label
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formatFocalLength(_ value: Double?, equivalent35mm: Double?) -> String {
        guard let value else { return "—" }
        let base = String(format: "%.0fmm", value)
        if let eq35 = equivalent35mm, abs(eq35 - value) > 0.5 {
            return "\(base) (≈\(Int(eq35))mm eq.)"
        }
        return base
    }

    private func formatFlash(fired: Bool?, mode: String?) -> String {
        guard fired != nil || mode != nil else { return "—" }
        let parts: [String] = [
            mode ?? "",
            fired == true ? "Fired" : (fired == false ? "Did not fire" : "")
        ].filter { !$0.isEmpty }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    private func formatExposureBias(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%+.1f EV", value)
    }

    private func formatDimensions(width: Int?, height: Int?) -> String {
        guard let width, let height else { return "—" }
        let megapixels = Double(width * height) / 1_000_000.0
        return "\(width) × \(height) (~\(String(format: "%.1f", megapixels)) MP)"
    }

    private func formatOrientation(_ value: Int?) -> String {
        guard let value else { return "—" }
        switch value {
        case 1: return "Normal (1)"
        case 2: return "Mirrored (2)"
        case 3: return "Rotated 180° (3)"
        case 4: return "Mirrored + 180° (4)"
        case 5: return "Mirrored + 270° (5)"
        case 6: return "Rotated 90° CW (6)"
        case 7: return "Mirrored + 90° CW (7)"
        case 8: return "Rotated 270° CW (8)"
        default: return "Unknown (\(value))"
        }
    }

    private func formatGPS(latitude: Double?, longitude: Double?) -> String {
        guard let latitude, let longitude else { return "—" }
        return String(format: "%.5f°, %.5f°", latitude, longitude)
    }

    private func formatAltitude(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f m", value)
    }
}

// MARK: - File list row

private struct FileListRow: View {
    let entry: FileBreakdownEntry
    @State private var isHovered = false

    private var chipColor: Color {
        switch entry.role {
        case .jpeg:   return Theme.Color.FileColor.jpeg
        case .heif:   return Theme.Color.FileColor.heif
        case .raw:    return Theme.Color.FileColor.raw
        case .edit:   return Theme.Color.warning
        case .other:  return Theme.Color.FileColor.other
        }
    }

    var body: some View {
        HStack(spacing: Theme.Space.s6) {
            Text(entry.roleLabel)
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .tracking(0.5)
                .foregroundStyle(Theme.Color.textInverse)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule().fill(chipColor)
                )
                .fixedSize()

            Text(entry.displayName)
                .font(Theme.Font.monoCaption)
                .foregroundStyle(Theme.Color.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(entry.url.path)
        }
        .padding(.horizontal, Theme.Space.s6)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.s)
                .fill(isHovered ? Theme.Color.rowSelectedFill.opacity(0.6) : Color.clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.s))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) { isHovered = hovering }
        }
        .contextMenu {
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([entry.url])
            }
            Button("Copy Filename") {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(entry.displayName, forType: .string)
            }
        }
    }
}
