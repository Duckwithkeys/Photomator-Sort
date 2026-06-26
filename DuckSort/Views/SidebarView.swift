//
//  SidebarView.swift
//  DuckSort
//

import SwiftUI

struct SidebarView: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Search
            HStack(spacing: Theme.Space.s6) {
                Image(systemName: "magnifyingglass")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.textSecondary)
                TextField("Search files…", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Color.textPrimary)
                    .focused($isSearchFocused)
                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Color.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.Space.s8)
            .padding(.vertical, Theme.Space.s4)
            .background(Theme.Color.cellBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.m))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.m)
                    .stroke(Theme.Color.separator, lineWidth: Theme.Stroke.hairline)
            )
            .padding(.horizontal, Theme.Space.s16)
            .padding(.bottom, Theme.Space.s8)

            // Permanent filter bar — stays put so it doesn't shift the
            // rest of the sidebar when the user picks or clears filters.
            // Greys out when no filters are active.
            ActiveFiltersBar(
                count: viewModel.activeFilterCount,
                isEmpty: viewModel.activeFilterCount == 0,
                onClear: viewModel.clearAllFilters
            )
            .padding(.horizontal, Theme.Space.s16)
            .padding(.bottom, Theme.Space.s8)

            List {
                LibrarySectionView(viewModel: viewModel)
                SourcesSectionView(viewModel: viewModel)
                TagsSectionView(viewModel: viewModel)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
        .frame(minWidth: 220, idealWidth: 240, maxWidth: 280)
        .background(Theme.Color.sidebarBackground)
        .onAppear {
            // Don't let the first responder auto-grab the search field;
            // keyboard shortcuts in the grid should work without the user
            // having to click out of the field first.
            isSearchFocused = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isSearchFocused = false
            }
        }
    }

    private var brandBar: some View {
        HStack(spacing: Theme.Space.s8) {
            Image("duck_logo")
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)

            Text("DuckSort")
                .font(Theme.Font.headline)
                .foregroundStyle(Theme.Color.textPrimary)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Space.s16)
        .padding(.bottom, Theme.Space.s12)
        .background(Theme.Color.sidebarBackground)
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
                } label: {
                    HStack {
                        Image(systemName: rule.systemImage)
                            .foregroundStyle(viewModel.filterRule == rule ? Theme.Color.accent : Theme.Color.textSecondary)
                            .frame(width: 16)
                        Text(rule.rawValue)
                            .foregroundStyle(Theme.Color.textPrimary)
                        Spacer()
                        let count = count(for: rule)
                        if count > 0 {
                            Text("\(count)")
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Color.textSecondary)
                        }
                    }
                    .padding(.vertical, Theme.Space.s4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.12)) {
                        hoveredRule = hovering ? rule : nil
                    }
                }
                .listRowBackground(
                    RoundedRectangle(cornerRadius: Theme.Radius.m)
                        .fill(
                            viewModel.filterRule == rule
                            ? Theme.Color.rowSelectedFill
                            : (hoveredRule == rule ? Theme.Color.rowHoverFill : Color.clear)
                        )
                        .padding(.horizontal, Theme.Space.s8)
                )
            }
        }
    }

    private func count(for rule: PhotoFilterRule) -> Int {
        switch rule {
        case .allPhotos:   return viewModel.cachedAllPhotosCount
        case .editedOnly:  return viewModel.cachedEditedCount
        case .uneditedOnly: return viewModel.cachedUneditedCount
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

            Button(action: { viewModel.addSourceDirectory() }) {
                HStack(spacing: Theme.Space.s8) {
                    Image(systemName: "plus.circle")
                        .foregroundStyle(Theme.Color.accent)
                        .frame(width: 16)
                    Text("Add Source…")
                        .foregroundStyle(Theme.Color.accent)
                }
                .padding(.vertical, Theme.Space.s4)
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
                    iconColor: Theme.Color.textInverse,
                    isSelected: viewModel.selectedFlags.contains(1),
                    count: viewModel.cachedFlagCounts[1] ?? 0,
                    action: { viewModel.toggleFlagFilter(1) }
                )
                SystemFilterRow(
                    name: "Rejected",
                    systemImage: "flag.slash.fill",
                    iconColor: Theme.Color.danger,
                    isSelected: viewModel.selectedFlags.contains(-1),
                    count: viewModel.cachedFlagCounts[-1] ?? 0,
                    action: { viewModel.toggleFlagFilter(-1) }
                )
                SystemFilterRow(
                    name: "Unrated",
                    systemImage: "star.slash",
                    iconColor: Theme.Color.textTertiary,
                    isSelected: viewModel.selectedRatings.contains(0),
                    count: viewModel.cachedRatingCounts[0] ?? 0,
                    action: { viewModel.toggleRatingFilter(0) }
                )
                ForEach((1...5).reversed(), id: \.self) { rating in
                    SystemFilterRow(
                        name: "\(rating) Star\(rating == 1 ? "" : "s")",
                        systemImage: "star.fill",
                        iconColor: Theme.Color.rating,
                        isSelected: viewModel.selectedRatings.contains(rating),
                        count: viewModel.cachedRatingCounts[rating] ?? 0,
                        action: { viewModel.toggleRatingFilter(rating) }
                    )
                }
            } label: {
                HStack {
                    Text("Flags & Ratings")
                        .font(Theme.Font.subheadline)
                        .foregroundStyle(Theme.Color.textPrimary)
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture { isFlagsExpanded.toggle() }
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.12)) { isFlagsHovered = hovering }
                }
            }
            .tint(Theme.Color.textSecondary)
            .listRowBackground(
                RoundedRectangle(cornerRadius: Theme.Radius.m)
                    .fill(isFlagsHovered ? Theme.Color.rowHoverFill : Color.clear)
                    .padding(.horizontal, Theme.Space.s8)
            )

            if viewModel.tagStore.tags.isEmpty {
                Text("No tags")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.textTertiary)
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
                                } label: {
                                    HStack {
                                        Circle()
                                            .fill(tag.color)
                                            .frame(width: 10, height: 10)
                                        Text(tag.name)
                                            .foregroundStyle(Theme.Color.textPrimary)
                                        Spacer()
                                        let count = viewModel.cachedTagCounts[tag.id] ?? 0
                                        if count > 0 {
                                            Text("\(count)")
                                                .font(Theme.Font.caption)
                                                .foregroundStyle(Theme.Color.textSecondary)
                                        }
                                    }
                                    .padding(.vertical, Theme.Space.s4)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .onHover { hovering in
                                    withAnimation(.easeInOut(duration: 0.12)) {
                                        hoveredTagID = hovering ? tag.id : nil
                                    }
                                }
                                .listRowBackground(
                                    RoundedRectangle(cornerRadius: Theme.Radius.m)
                                        .fill(
                                            viewModel.selectedTagFilters.contains(tag.id)
                                            ? Theme.Color.rowSelectedFill
                                            : (hoveredTagID == tag.id ? Theme.Color.rowHoverFill : Color.clear)
                                        )
                                        .padding(.horizontal, Theme.Space.s8)
                                )
                            }
                        } label: {
                            HStack {
                                Text(category.name)
                                    .font(Theme.Font.subheadline)
                                    .foregroundStyle(Theme.Color.textPrimary)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { isExpandedBinding.wrappedValue.toggle() }
                            .onHover { hovering in
                                withAnimation(.easeInOut(duration: 0.12)) {
                                    hoveredCategoryID = hovering ? category.id : nil
                                }
                            }
                        }
                        .tint(Theme.Color.textSecondary)
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: Theme.Radius.m)
                                .fill(hoveredCategoryID == category.id ? Theme.Color.rowHoverFill : Color.clear)
                                .padding(.horizontal, Theme.Space.s8)
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
                .foregroundStyle(hasError ? Theme.Color.danger : Theme.Color.textSecondary)
                .frame(width: 16)
            Text(url.lastPathComponent)
                .foregroundStyle(hasError ? Theme.Color.danger : Theme.Color.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)

            if hasError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.danger)
                    .help("Failed to read this source")
            }

            Spacer()

            if isHovered {
                HStack(spacing: Theme.Space.s8) {
                    Button(action: onReveal) {
                        Image(systemName: "magnifyingglass")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Color.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .help("Reveal in Finder")

                    Button(action: onRemove) {
                        Image(systemName: "xmark.circle")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Color.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .help(isFolder ? "Remove source folder" : "Remove source file")
                }
            }
        }
        .padding(.vertical, Theme.Space.s4)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovered = hovering }
        }
        .contextMenu {
            Button("Reveal in Finder") { onReveal() }
            Button(isFolder ? "Remove Source Folder" : "Remove Source File") { onRemove() }
        }
        .listRowBackground(
            RoundedRectangle(cornerRadius: Theme.Radius.m)
                .fill(isHovered ? Theme.Color.rowHoverFill : Color.clear)
                .padding(.horizontal, Theme.Space.s8)
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
                    .foregroundStyle(Theme.Color.textPrimary)
                Spacer()
                if count > 0 {
                    Text("\(count)")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Color.textSecondary)
                }
            }
            .padding(.vertical, Theme.Space.s4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovered = hovering }
        }
        .listRowBackground(
            RoundedRectangle(cornerRadius: Theme.Radius.m)
                .fill(
                    isSelected
                    ? Theme.Color.rowSelectedFill
                    : (isHovered ? Theme.Color.rowHoverFill : Color.clear)
                )
                .padding(.horizontal, Theme.Space.s8)
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
            .tint(Theme.Color.textSecondary)
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
        }) {
            HStack {
                Image(systemName: "folder")
                    .foregroundStyle(isSelected ? Theme.Color.accent : Theme.Color.textSecondary)
                    .frame(width: 12, height: 12)
                Text(name)
                    .font(Theme.Font.subheadline)
                    .foregroundStyle(Theme.Color.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if count > 0 {
                    Text("\(count)")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Color.textSecondary)
                }
            }
            .padding(.vertical, Theme.Space.s4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovered = hovering }
        }
        .listRowBackground(
            RoundedRectangle(cornerRadius: Theme.Radius.m)
                .fill(
                    isSelected
                    ? Theme.Color.rowSelectedFill
                    : (isHovered ? Theme.Color.rowHoverFill : Color.clear)
                )
                .padding(.horizontal, Theme.Space.s8)
        )
    }
}

// MARK: - Active Filters Bar

struct ActiveFiltersBar: View {
    let count: Int
    let isEmpty: Bool
    let onClear: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Theme.Space.s6) {
            Image(systemName: isEmpty
                  ? "line.3.horizontal.decrease.circle"
                  : "line.3.horizontal.decrease.circle.fill")
                .foregroundStyle(isEmpty ? Theme.Color.textTertiary : Theme.Color.accent)
                .font(Theme.Font.subheadline)

            Text(isEmpty
                 ? "No active filters"
                 : "^[\(count) active filter](inflect: true)")
                .font(Theme.Font.caption)
                .foregroundStyle(isEmpty ? Theme.Color.textTertiary : Theme.Color.textPrimary)
                .lineLimit(1)

            Spacer(minLength: Theme.Space.s4)

            Button(action: onClear) {
                Text("Clear")
                    .font(Theme.Font.caption)
                    .foregroundStyle(isEmpty ? Theme.Color.textTertiary : Theme.Color.accent)
                    .padding(.horizontal, Theme.Space.s8)
                    .padding(.vertical, Theme.Space.s2)
                    .background(
                        isHovered && !isEmpty
                            ? Theme.Color.rowSelectedFill
                            : Color.clear,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.s)
                    )
            }
            .buttonStyle(.plain)
            .disabled(isEmpty)
            .help(isEmpty
                  ? "Pick a tag, rating, or flag in the list below to filter the grid."
                  : "Clear all filters and search")
        }
        .padding(.horizontal, Theme.Space.s8)
        .padding(.vertical, Theme.Space.s4)
        .background(
            isEmpty
                ? Theme.Color.surfaceRaised.opacity(0.4)
                : Theme.Color.rowSelectedFill,
            in: RoundedRectangle(cornerRadius: Theme.Radius.m)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.m)
                .stroke(
                    isEmpty
                        ? Theme.Color.surfaceDivider
                        : Theme.Color.accent.opacity(0.3),
                    lineWidth: Theme.Stroke.hairline
                )
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovered = hovering }
        }
    }
}
