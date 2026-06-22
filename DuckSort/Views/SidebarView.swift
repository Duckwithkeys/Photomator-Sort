//
//  SidebarView.swift
//  PhotomatorSort
//

import SwiftUI

struct SidebarView: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 38) // Space for macOS traffic lights

            // Header Branding
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
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            // Premium linear gradient separator
            LinearGradient(
                colors: [PhotomatorTheme.selectedBlue, PhotomatorTheme.selectedBlue.opacity(0.1)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 1)
            .padding(.horizontal, 16)
            .padding(.bottom, 10)

            // Search Bar (colored the same as the sidebar background with a border outline)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(PhotomatorTheme.textSecondary)
                TextField("Search files...", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(PhotomatorTheme.textPrimary)
                    .focused($isSearchFocused)
                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(PhotomatorTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(PhotomatorTheme.sidebarBackground, in: RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(PhotomatorTheme.separator, lineWidth: 1)
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            // Sidebar list sections
            List {
                LibrarySectionView(viewModel: viewModel)
                SourcesSectionView(viewModel: viewModel)
                TagsSectionView(viewModel: viewModel)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .onTapGesture {
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
        }
        .frame(minWidth: 160, idealWidth: 180, maxWidth: 240)
        .background(PhotomatorTheme.sidebarBackground)
        .onAppear {
            isSearchFocused = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                isSearchFocused = false
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
        }
    }
}

// MARK: - Library Section View
struct LibrarySectionView: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel
    @State private var hoveredRule: PhotoFilterRule? = nil

    var body: some View {
        Section("LIBRARY") {
            ForEach(PhotoFilterRule.allCases) { rule in
                Button {
                    viewModel.filterRule = rule
                    NSApp.keyWindow?.makeFirstResponder(nil)
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
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.12)) {
                        hoveredRule = hovering ? rule : nil
                    }
                }
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            viewModel.filterRule == rule
                            ? PhotomatorTheme.selectedBlue.opacity(0.15)
                            : (hoveredRule == rule ? Color.primary.opacity(0.05) : Color.clear)
                        )
                        .padding(.horizontal, 8)
                )
            }
        }
    }

    private func count(for rule: PhotoFilterRule) -> Int {
        switch rule {
        case .allPhotos:
            return viewModel.cachedAllPhotosCount
        case .editedOnly:
            return viewModel.cachedEditedCount
        case .uneditedOnly:
            return viewModel.cachedUneditedCount
        }
    }
}

// MARK: - Sources Section View
struct SourcesSectionView: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel

    var body: some View {
        Section("SOURCES") {
            ForEach(viewModel.sourceDirectories, id: \.self) { url in
                SourceSectionRow(viewModel: viewModel, url: url)
            }

            ForEach(viewModel.looseFiles, id: \.self) { url in
                SourceRow(
                    url: url,
                    isFolder: false,
                    hasError: viewModel.failedSources.contains(url),
                    onReveal: {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    },
                    onRemove: {
                        viewModel.removeLooseFile(url)
                    }
                )
            }

            Button(action: {
                viewModel.addSourceDirectory()
                NSApp.keyWindow?.makeFirstResponder(nil)
            }) {
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
    }
}

// MARK: - Tags Section View
struct TagsSectionView: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel
    @State private var hoveredTagID: UUID? = nil
    @State private var isFlagsExpanded = true
    @State private var isFlagsHovered = false
    @State private var expandedCategoryIDs: Set<UUID> = []
    @State private var hoveredCategoryID: UUID? = nil

    var body: some View {
        Section("TAGS") {
            DisclosureGroup(isExpanded: $isFlagsExpanded) {
                SystemFilterRow(
                    name: "Flagged",
                    systemImage: "flag.fill",
                    iconColor: .white,
                    isSelected: viewModel.selectedFlags.contains(1),
                    count: viewModel.cachedFlagCounts[1] ?? 0,
                    action: { viewModel.toggleFlagFilter(1) }
                )
                SystemFilterRow(
                    name: "Rejected",
                    systemImage: "flag.slash.fill",
                    iconColor: .red,
                    isSelected: viewModel.selectedFlags.contains(-1),
                    count: viewModel.cachedFlagCounts[-1] ?? 0,
                    action: { viewModel.toggleFlagFilter(-1) }
                )
                SystemFilterRow(
                    name: "Unrated",
                    systemImage: "star.slash",
                    iconColor: .gray,
                    isSelected: viewModel.selectedRatings.contains(0),
                    count: viewModel.cachedRatingCounts[0] ?? 0,
                    action: { viewModel.toggleRatingFilter(0) }
                )
                ForEach((1...5).reversed(), id: \.self) { rating in
                    SystemFilterRow(
                        name: "\(rating) Star\(rating == 1 ? "" : "s")",
                        systemImage: "star.fill",
                        iconColor: .yellow,
                        isSelected: viewModel.selectedRatings.contains(rating),
                        count: viewModel.cachedRatingCounts[rating] ?? 0,
                        action: { viewModel.toggleRatingFilter(rating) }
                    )
                }
            } label: {
                HStack {
                    Text("Flags & Ratings")
                        .font(.subheadline)
                        .foregroundStyle(PhotomatorTheme.textPrimary)
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    isFlagsExpanded.toggle()
                }
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.12)) {
                        isFlagsHovered = hovering
                    }
                }
            }
            .tint(PhotomatorTheme.textSecondary)
            .listRowBackground(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isFlagsHovered ? Color.primary.opacity(0.05) : Color.clear)
                    .padding(.horizontal, 8)
            )

            if viewModel.tagStore.tags.isEmpty {
                Text("No tags")
                    .font(.caption)
                    .foregroundStyle(PhotomatorTheme.textTertiary)
            } else {
                ForEach(viewModel.tagStore.categories) { category in
                    let tagsInCategory = viewModel.tagStore.tags(in: category.id)
                    if !tagsInCategory.isEmpty {
                        let isExpandedBinding = Binding<Bool>(
                            get: { expandedCategoryIDs.contains(category.id) },
                            set: { isExpanded in
                                if isExpanded {
                                    expandedCategoryIDs.insert(category.id)
                                } else {
                                    expandedCategoryIDs.remove(category.id)
                                }
                            }
                        )
                        DisclosureGroup(isExpanded: isExpandedBinding) {
                            ForEach(tagsInCategory) { tag in
                                Button {
                                    if viewModel.selectedTagFilters.contains(tag.id) {
                                        viewModel.selectedTagFilters.remove(tag.id)
                                    } else {
                                        viewModel.selectedTagFilters.insert(tag.id)
                                    }
                                    NSApp.keyWindow?.makeFirstResponder(nil)
                                } label: {
                                    HStack {
                                        Circle()
                                            .fill(tag.color)
                                            .frame(width: 10, height: 10)
                                        Text(tag.name)
                                            .foregroundStyle(PhotomatorTheme.textPrimary)
                                        Spacer()
                                        let count = viewModel.cachedTagCounts[tag.id] ?? 0
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
                                .onHover { hovering in
                                    withAnimation(.easeInOut(duration: 0.12)) {
                                        hoveredTagID = hovering ? tag.id : nil
                                    }
                                }
                                .listRowBackground(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(
                                            viewModel.selectedTagFilters.contains(tag.id)
                                            ? PhotomatorTheme.selectedBlue.opacity(0.15)
                                            : (hoveredTagID == tag.id ? Color.primary.opacity(0.05) : Color.clear)
                                        )
                                        .padding(.horizontal, 8)
                                )
                            }
                        } label: {
                            HStack {
                                Text(category.name)
                                    .font(.subheadline)
                                    .foregroundStyle(PhotomatorTheme.textPrimary)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                isExpandedBinding.wrappedValue.toggle()
                            }
                            .onHover { hovering in
                                withAnimation(.easeInOut(duration: 0.12)) {
                                    hoveredCategoryID = hovering ? category.id : nil
                                }
                            }
                        }
                        .tint(PhotomatorTheme.textSecondary)
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(hoveredCategoryID == category.id ? Color.primary.opacity(0.05) : Color.clear)
                                .padding(.horizontal, 8)
                        )
                    }
                }
            }
        }
        .onAppear {
            if expandedCategoryIDs.isEmpty {
                expandedCategoryIDs = Set(viewModel.tagStore.categories.map(\.id))
            }
        }
    }
}

// MARK: - Component Row Views
struct SourceRow: View {
    let url: URL
    let isFolder: Bool
    let hasError: Bool
    let onReveal: () -> Void
    let onRemove: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack {
            Image(systemName: isFolder ? "folder" : "photo")
                .foregroundStyle(hasError ? Color.red : PhotomatorTheme.textSecondary)
                .frame(width: 16)
            Text(url.lastPathComponent)
                .foregroundStyle(hasError ? Color.red : PhotomatorTheme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)

            if hasError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .help("Failed to read this source")
            }

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
                    .help(isFolder ? "Remove source folder" : "Remove source file")
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
        .contextMenu {
            Button("Reveal in Finder") {
                onReveal()
            }
            Button(isFolder ? "Remove Source Folder" : "Remove Source File") {
                onRemove()
            }
        }
        .listRowBackground(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.primary.opacity(0.05) : Color.clear)
                .padding(.horizontal, 8)
        )
    }
}

struct SystemFilterRow: View {
    let name: String
    let systemImage: String
    let iconColor: Color
    let isSelected: Bool
    let count: Int
    let action: () -> Void
    @State private var isHovered = false

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
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
        .listRowBackground(
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    isSelected
                    ? PhotomatorTheme.selectedBlue.opacity(0.15)
                    : (isHovered ? Color.primary.opacity(0.05) : Color.clear)
                )
                .padding(.horizontal, 8)
        )
    }
}

// MARK: - Custom Section / Subfolder Rows
struct SourceSectionRow: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel
    let url: URL
    @State private var isExpanded = false

    var body: some View {
        let subfolders = viewModel.cachedSubfolders[url] ?? []
        if subfolders.count > 1 {
            DisclosureGroup(isExpanded: $isExpanded) {
                ForEach(subfolders, id: \.self) { subfolder in
                    SubfolderRow(viewModel: viewModel, subfolder: subfolder, parentSource: url)
                }
            } label: {
                SourceRow(
                    url: url,
                    isFolder: true,
                    hasError: viewModel.failedSources.contains(url),
                    onReveal: {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    },
                    onRemove: {
                        viewModel.removeSourceDirectory(url)
                    }
                )
            }
            .tint(PhotomatorTheme.textSecondary)
        } else {
            SourceRow(
                url: url,
                isFolder: true,
                hasError: viewModel.failedSources.contains(url),
                onReveal: {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                },
                onRemove: {
                    viewModel.removeSourceDirectory(url)
                }
            )
        }
    }
}

struct SubfolderRow: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel
    let subfolder: URL
    let parentSource: URL
    @State private var isHovered = false

    var body: some View {
        let isSelected = viewModel.selectedSubfolderFilter == subfolder
        let name = viewModel.relativePath(of: subfolder, relativeTo: parentSource)
        let count = viewModel.cachedSubfolderCounts[subfolder] ?? 0

        Button(action: {
            if isSelected {
                viewModel.selectedSubfolderFilter = nil
            } else {
                viewModel.selectedSubfolderFilter = subfolder
            }
            NSApp.keyWindow?.makeFirstResponder(nil)
        }) {
            HStack {
                Image(systemName: "folder")
                    .foregroundStyle(isSelected ? PhotomatorTheme.selectedBlue : PhotomatorTheme.textSecondary)
                    .frame(width: 12, height: 12)
                Text(name)
                    .font(.subheadline)
                    .foregroundStyle(PhotomatorTheme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
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
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
        .listRowBackground(
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    isSelected
                    ? PhotomatorTheme.selectedBlue.opacity(0.15)
                    : (isHovered ? Color.primary.opacity(0.05) : Color.clear)
                )
                .padding(.horizontal, 8)
        )
    }
}
