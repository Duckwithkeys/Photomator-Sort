//
//  LargeImageViewerSidebar.swift
//  DuckSort
//

import SwiftUI

struct LargeImageViewerSidebar: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel

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
                                metadataField(label: "Files in Set", value: "\(photo.mediaCount) files\(photo.hasEdit ? " + edit" : "")",
                                              systemImage: photo.hasEdit ? "wand.and.stars" : "link",
                                              iconColor: photo.hasEdit ? Theme.Color.warning : Theme.Color.textSecondary)
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

                    // Section 3: Export Preview
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

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
