//
//  LargeImageViewerSidebar.swift
//  PhotomatorSort
//

import SwiftUI

struct LargeImageViewerSidebar: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    
                    // MARK: - Section 1: Tags
                    VStack(alignment: .leading, spacing: 10) {
                        Text("ACTIVE TAGS")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)

                        if let photo = viewModel.currentFocusedPhotoSet {
                            let assignedTags = viewModel.assignedTags(for: photo)
                            
                            if assignedTags.isEmpty {
                                Text("No tags applied")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(assignedTags) { tag in
                                        HStack(spacing: 6) {
                                            Circle()
                                                .fill(tag.color)
                                                .frame(width: 8, height: 8)
                                            Text(tag.name)
                                                .font(.caption.weight(.medium))
                                                .foregroundStyle(.primary)
                                            
                                            Spacer()
                                            
                                            Button {
                                                viewModel.removeTag(tag, from: photo.id)
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                            .buttonStyle(.plain)
                                            .help("Remove tag")
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 5)
                                        .background(tag.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                                    }
                                }
                            }
                        } else {
                            Text("No photo selected")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider()
                        .background(Color.white.opacity(0.12))

                    // MARK: - Section 2: Metadata
                    VStack(alignment: .leading, spacing: 12) {
                        Text("IMAGE METADATA")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)

                        if let photo = viewModel.currentFocusedPhotoSet {
                            let meta = viewModel.metadata(for: photo)
                            
                            VStack(alignment: .leading, spacing: 10) {
                                metadataField(label: "Filename", value: photo.baseName, systemImage: "photo")
                                metadataField(label: "Files in Set", value: "\(photo.mediaCount) files\(photo.hasEdit ? " + edit" : "")", systemImage: "link")
                                metadataField(label: "Captured", value: meta.captureDate.map(formatDate) ?? "—", systemImage: "calendar")
                                metadataField(label: "Camera", value: meta.cameraModel ?? "—", systemImage: "camera")
                                metadataField(label: "Lens", value: meta.lensModel ?? "—", systemImage: "camera.macro")
                            }
                        } else {
                            Text("No photo selected")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider()
                        .background(Color.white.opacity(0.12))

                    // MARK: - Section 3: Export Preview
                    VStack(alignment: .leading, spacing: 10) {
                        Text("ROUTED EXPORT PREVIEW")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)

                        if let photo = viewModel.currentFocusedPhotoSet {
                            let meta = viewModel.metadata(for: photo)
                            let tags = viewModel.assignedTags(for: photo)

                            VStack(alignment: .leading, spacing: 8) {
                                if let rule = viewModel.ruleStore.selectedRule {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Active Rule")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(rule.name)
                                            .font(.caption.weight(.medium))
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

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(folders.count <= 1 ? "Folder Destination" : "Folder Destinations")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            ForEach(folders, id: \.self) { folder in
                                                Text(folder.path)
                                                    .font(.caption2.monospaced())
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(2)
                                                    .truncationMode(.middle)
                                            }
                                        }
                                    }
                                } else {
                                    Text("No rule selected")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
                .padding(14)
            }
        }
        .frame(width: 260)
        .background(.thinMaterial)
        .border(width: 1, edges: [.leading], color: Color.white.opacity(0.12))
    }

    // MARK: - Helper Views / Formatters

    private func metadataField(label: String, value: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 14, alignment: .center)
                .padding(.top, 2)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
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



// MARK: - Border Modifier Helper

extension View {
    func border(width: CGFloat, edges: [Edge], color: Color) -> some View {
        overlay(EdgeBorder(width: width, edges: edges).foregroundColor(color))
    }
}

struct EdgeBorder: Shape {
    var width: CGFloat
    var edges: [Edge]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for edge in edges {
            var x: CGFloat {
                switch edge {
                case .top, .bottom, .leading: return rect.minX
                case .trailing: return rect.maxX - width
                }
            }

            var y: CGFloat {
                switch edge {
                case .top, .leading, .trailing: return rect.minY
                case .bottom: return rect.maxY - width
                }
            }

            var w: CGFloat {
                switch edge {
                case .top, .bottom: return rect.width
                case .leading, .trailing: return width
                }
            }

            var h: CGFloat {
                switch edge {
                case .top, .bottom: return width
                case .leading, .trailing: return rect.height
                }
            }

            path.addRect(CGRect(x: x, y: y, width: w, height: h))
        }
        return path
    }
}
