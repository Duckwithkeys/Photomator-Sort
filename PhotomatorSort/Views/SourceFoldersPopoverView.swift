//
//  SourceFoldersPopoverView.swift
//  PhotomatorSort
//
//  Popover that lists loaded source folders and lets the user add or remove them.
//

import SwiftUI

struct SourceFoldersPopoverView: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Source Folders")
                    .font(.headline)
                Spacer()
                Button {
                    viewModel.addSourceDirectory()
                } label: {
                    Image(systemName: "plus")
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderless)
                .help("Add a source folder")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            if viewModel.sourceDirectories.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("No source folders added")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Add Folder…") {
                        viewModel.addSourceDirectory()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(viewModel.sourceDirectories, id: \.path) { url in
                            SourceFolderRow(url: url) {
                                viewModel.removeSourceDirectory(url)
                            }
                            Divider()
                                .padding(.leading, 36)
                        }
                    }
                }
                .frame(maxHeight: 240)

                Divider()

                // Footer: add + clear
                HStack(spacing: 10) {
                    Button("Add Folder…") {
                        viewModel.addSourceDirectory()
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    if viewModel.sourceDirectories.count > 1 {
                        Button("Remove All") {
                            viewModel.clearSourceDirectories()
                        }
                        .foregroundStyle(.red)
                        .buttonStyle(.borderless)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
        .frame(width: 320)
    }
}

// MARK: - Row

private struct SourceFolderRow: View {
    let url: URL
    let onRemove: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder.fill")
                .foregroundStyle(.blue)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(url.lastPathComponent)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(url.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .opacity(isHovered ? 1 : 0)
            .help("Remove this source folder")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}
