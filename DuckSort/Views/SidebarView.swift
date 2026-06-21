//
//  SidebarView.swift
//  PhotomatorSort
//

import SwiftUI

struct SidebarView: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 38) // Space for macOS traffic lights

            HStack(spacing: 8) {
                let img: NSImage = {
                    if let path = Bundle.module.path(forResource: "duck_logo", ofType: "png"),
                       let image = NSImage(contentsOfFile: path) {
                        return image
                    }
                    if let image = Bundle.module.image(forResource: "duck_logo") {
                        return image
                    }
                    if let image = Bundle.module.image(forResource: "AppIcon") {
                        return image
                    }
                    if let path = Bundle.module.path(forResource: "AppIcon", ofType: "icns"),
                       let image = NSImage(contentsOfFile: path) {
                        return image
                    }
                    return NSApplication.shared.applicationIconImage ?? NSImage()
                }()
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
                
                Text("DuckSort")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(PhotomatorTheme.textPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            // Accent blue separator to create a clear break
            Rectangle()
                .fill(PhotomatorTheme.selectedBlue)
                .frame(height: 1)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            List {
                // MARK: - Library Section
                Section("LIBRARY") {
                    ForEach(PhotoFilterRule.allCases) { rule in
                        Button {
                            viewModel.filterRule = rule
                        } label: {
                            HStack {
                                Image(systemName: rule.systemImage)
                                    .foregroundStyle(viewModel.filterRule == rule ? PhotomatorTheme.selectedBlue : PhotomatorTheme.textSecondary)
                                    .frame(width: 16)
                                Text(rule.rawValue)
                                    .foregroundStyle(PhotomatorTheme.textPrimary)
                                Spacer()
                                // Count badge
                                let count = count(for: rule)
                                if count > 0 {
                                    Text("\(count)")
                                        .font(.caption)
                                        .foregroundStyle(PhotomatorTheme.textSecondary)
                                }
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(viewModel.filterRule == rule ? PhotomatorTheme.selectedBlue.opacity(0.15) : Color.clear)
                                .padding(.horizontal, 8)
                        )
                    }
                }
                
                // MARK: - Sources Section
                Section("SOURCES") {
                    ForEach(viewModel.sourceDirectories, id: \.self) { url in
                        SourceRow(
                            url: url,
                            onReveal: {
                                NSWorkspace.shared.activateFileViewerSelecting([url])
                            },
                            onRemove: {
                                viewModel.removeSourceDirectory(url)
                            }
                        )
                    }

                    Button(action: { viewModel.addSourceDirectory() }) {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle")
                                .foregroundStyle(PhotomatorTheme.selectedBlue)
                                .frame(width: 16)
                            Text("Add Source...")
                                .foregroundStyle(PhotomatorTheme.selectedBlue)
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                }
                
                
                // MARK: - Tags Section
                Section("TAGS") {
                    DisclosureGroup {
                        SystemFilterRow(
                            name: "Flagged",
                            systemImage: "flag.fill",
                            iconColor: .white,
                            isSelected: viewModel.selectedFlags.contains(1),
                            count: countForFlag(1),
                            action: { viewModel.toggleFlagFilter(1) }
                        )
                        SystemFilterRow(
                            name: "Rejected",
                            systemImage: "flag.slash.fill",
                            iconColor: .red,
                            isSelected: viewModel.selectedFlags.contains(-1),
                            count: countForFlag(-1),
                            action: { viewModel.toggleFlagFilter(-1) }
                        )
                        SystemFilterRow(
                            name: "Unrated",
                            systemImage: "star.slash",
                            iconColor: .gray,
                            isSelected: viewModel.selectedRatings.contains(0),
                            count: countForRating(0),
                            action: { viewModel.toggleRatingFilter(0) }
                        )
                        ForEach((1...5).reversed(), id: \.self) { rating in
                            SystemFilterRow(
                                name: "\(rating) Star\(rating == 1 ? "" : "s")",
                                systemImage: "star.fill",
                                iconColor: .yellow,
                                isSelected: viewModel.selectedRatings.contains(rating),
                                count: countForRating(rating),
                                action: { viewModel.toggleRatingFilter(rating) }
                            )
                        }
                    } label: {
                        Text("Flags & Ratings")
                            .font(.subheadline)
                            .foregroundStyle(PhotomatorTheme.textPrimary)
                    }
                    .tint(PhotomatorTheme.textSecondary)

                    if viewModel.tagStore.tags.isEmpty {
                        Text("No tags")
                            .font(.caption)
                            .foregroundStyle(PhotomatorTheme.textTertiary)
                    } else {
                        ForEach(viewModel.tagStore.categories) { category in
                            let tagsInCategory = viewModel.tagStore.tags(in: category.id)
                            if !tagsInCategory.isEmpty {
                                DisclosureGroup {
                                    ForEach(tagsInCategory) { tag in
                                        Button {
                                            if viewModel.selectedTagFilters.contains(tag.id) {
                                                viewModel.selectedTagFilters.remove(tag.id)
                                            } else {
                                                viewModel.selectedTagFilters.insert(tag.id)
                                            }
                                        } label: {
                                            HStack {
                                                Circle()
                                                    .fill(tag.color)
                                                    .frame(width: 10, height: 10)
                                                Text(tag.name)
                                                    .foregroundStyle(PhotomatorTheme.textPrimary)
                                                Spacer()
                                                let count = count(forTag: tag.id)
                                                if count > 0 {
                                                    Text("\(count)")
                                                        .font(.caption)
                                                        .foregroundStyle(PhotomatorTheme.textSecondary)
                                                }
                                            }
                                            .padding(.vertical, 4)
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                        .listRowBackground(
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(viewModel.selectedTagFilters.contains(tag.id) ? PhotomatorTheme.selectedBlue.opacity(0.15) : Color.clear)
                                                .padding(.horizontal, 8)
                                        )
                                    }
                                } label: {
                                    Text(category.name)
                                        .font(.subheadline)
                                        .foregroundStyle(PhotomatorTheme.textPrimary)
                                }
                                .tint(PhotomatorTheme.textSecondary)
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
        .frame(minWidth: 160, idealWidth: 180, maxWidth: 240)
        .background(PhotomatorTheme.sidebarBackground)
    }
    
    private func count(for rule: PhotoFilterRule) -> Int {
        switch rule {
        case .allPhotos:
            return viewModel.photoSets.count
        case .editedOnly:
            return viewModel.editedCount
        case .uneditedOnly:
            return viewModel.uneditedCount
        }
    }
    
    private func count(forTag tagID: UUID) -> Int {
        viewModel.photoSets.filter { viewModel.tagStore.assignedTagIDs(for: $0.id).contains(tagID) }.count
    }

    private func countForFlag(_ flag: Int) -> Int {
        viewModel.photoSets.filter { $0.pick == flag }.count
    }

    private func countForRating(_ rating: Int) -> Int {
        viewModel.photoSets.filter { ($0.rating ?? 0) == rating }.count
    }
}

struct SourceRow: View {
    let url: URL
    let onReveal: () -> Void
    let onRemove: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack {
            Image(systemName: "folder")
                .foregroundStyle(PhotomatorTheme.textSecondary)
                .frame(width: 16)
            Text(url.lastPathComponent)
                .foregroundStyle(PhotomatorTheme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            if isHovered {
                HStack(spacing: 8) {
                    Button(action: onReveal) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11))
                            .foregroundStyle(PhotomatorTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .help("Reveal in Finder")

                    Button(action: onRemove) {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 11))
                            .foregroundStyle(PhotomatorTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove source")
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            Button("Reveal in Finder") {
                onReveal()
            }
            Button("Remove Source") {
                onRemove()
            }
        }
        .listRowBackground(Color.clear)
    }
}

struct SystemFilterRow: View {
    let name: String
    let systemImage: String
    let iconColor: Color
    let isSelected: Bool
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: systemImage)
                    .foregroundStyle(iconColor)
                    .frame(width: 12, height: 12)
                Text(name)
                    .foregroundStyle(PhotomatorTheme.textPrimary)
                Spacer()
                if count > 0 {
                    Text("\(count)")
                        .font(.caption)
                        .foregroundStyle(PhotomatorTheme.textSecondary)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? PhotomatorTheme.selectedBlue.opacity(0.15) : Color.clear)
                .padding(.horizontal, 8)
        )
    }
}

