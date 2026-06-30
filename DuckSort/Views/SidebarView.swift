//
//  SidebarView.swift
//  DuckSort
//

import SwiftUI

struct SidebarView: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel
    @State private var expandedFolderPaths: Set<String> = []
    @State private var isTagsExpanded: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Permanent filter bar — stays put so it doesn't shift the
            // rest of the sidebar when the user picks or clears filters.
            // Greys out when no filters are active.
            ActiveTagsBar(
                count: viewModel.selectedTagFilters.count,
                isEmpty: viewModel.selectedTagFilters.isEmpty,
                isExpanded: $isTagsExpanded,
                onClear: {
                    withAnimation(.smooth(duration: 0.15)) {
                        viewModel.selectedTagFilters.removeAll()
                    }
                }
            )
            .padding(.horizontal, Theme.Space.s16)
            .padding(.top, Theme.Space.s16)
            .padding(.bottom, Theme.Space.s8)

            List {
                if isTagsExpanded {
                    ActiveTagsDetailSectionView(viewModel: viewModel)
                }
                LibrarySectionView(viewModel: viewModel)
                SourcesSectionView(viewModel: viewModel, expandedFolderPaths: $expandedFolderPaths)
                TagsSectionView(viewModel: viewModel)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
        .frame(minWidth: 220, idealWidth: 240, maxWidth: 280)
        .background(Theme.Color.sidebarBackground)
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


// MARK: - Sources Section View

struct SourcesSectionView: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel
    @Binding var expandedFolderPaths: Set<String>

    var body: some View {
        Section("SOURCES") {
            ForEach(viewModel.sourceDirectories, id: \.self) { url in
                FolderTreeNode(
                    viewModel: viewModel,
                    folder: url,
                    parentSource: url,
                    depth: 0,
                    isRoot: true,
                    expandedFolderPaths: $expandedFolderPaths
                )
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
    @State private var expandedCategoryIDs: Set<UUID> = []
    @State private var hoveredCategoryID: UUID? = nil

    var body: some View {
        Section("TAGS") {

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

private func iconNameForFolder(_ folder: URL) -> String {
    let name = folder.lastPathComponent.lowercased()
    if name == "documents" { return "doc.folder.fill" }
    if name == "downloads" { return "arrow.down.folder.fill" }
    if name == "desktop" { return "desktopcomputer" }
    if name.contains("archive") { return "archivebox.fill" }
    if name.contains("creative") { return "paintpalette.fill" }
    if name.contains("media") || name.contains("pictures") || name.contains("photos") { return "photo.on.rectangle.fill" }
    if name.contains("project") { return "shippingbox.fill" }
    if name.contains("graph") { return "chart.bar.fill" }
    if name.contains("permaculture") || name.contains("garden") { return "leaf.fill" }
    return "folder.fill"
}

private func iconColorForFolder(_ folder: URL) -> Color {
    let name = folder.lastPathComponent.lowercased()
    if name == "documents" || name == "downloads" || name == "desktop" {
        return Color.blue
    }
    if name.contains("archive") || name.contains("creative") || name.contains("media") || name.contains("pictures") || name.contains("photos") || name.contains("project") || name.contains("graph") || name.contains("permaculture") || name.contains("garden") {
        return Theme.Color.textSecondary
    }
    return Color.blue // Default standard folder is blue
}

struct FolderTreeNode: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel
    let folder: URL
    let parentSource: URL
    let depth: Int
    let isRoot: Bool
    @Binding var expandedFolderPaths: Set<String>

    @State private var isHovered: Bool = false

    /// Subfolder children are computed once on first expansion, then cached
    /// in `@State` so expanding/collapsing doesn't re-walk `photoSets`.
    @State private var cachedChildren: [URL]? = nil

    /// Photo sets directly in this folder (not in subfolders) are computed
    /// once on first expansion, then cached in `@State`.
    @State private var cachedPhotos: [PhotoSet]? = nil

    private var hasFailed: Bool {
        isRoot && viewModel.failedSources.contains(folder)
    }

    private var isSubtreeSelected: Bool {
        guard let active = viewModel.selectedSubfolderFilter else { return false }
        let activePath = active.standardizedFileURL.path
        let folderPath = folder.standardizedFileURL.path
        return activePath == folderPath
            || (activePath.count > folderPath.count
                && activePath.hasPrefix(folderPath)
                && activePath[folderPath.endIndex] == "/")
    }

    private var isSelected: Bool {
        guard let active = viewModel.selectedSubfolderFilter else { return false }
        return active.standardizedFileURL.path == folder.standardizedFileURL.path
    }

    private var displayName: String {
        if isRoot { return folder.lastPathComponent.isEmpty ? folder.path : folder.lastPathComponent }
        return folder.lastPathComponent
    }

    private var photoCount: Int { viewModel.recursivePhotoCount(in: folder) }

    private var isExpanded: Binding<Bool> {
        Binding(
            get: { expandedFolderPaths.contains(folder.path) },
            set: { expand in
                if expand {
                    ensureChildrenLoaded()
                    expandedFolderPaths.insert(folder.path)
                } else {
                    expandedFolderPaths.remove(folder.path)
                }
            }
        )
    }

    private func ensureChildrenLoaded() {
        if cachedChildren == nil {
            cachedChildren = viewModel.childSubfolders(of: folder)
        }
        if cachedPhotos == nil {
            cachedPhotos = viewModel.photoSetsDirectlyIn(folder: folder)
        }
    }

    var body: some View {
        if canExpand {
            DisclosureGroup(isExpanded: isExpanded) {
                // Render child subfolders.
                if let children = cachedChildren, !children.isEmpty {
                    ForEach(children, id: \.self) { child in
                        FolderTreeNode(
                            viewModel: viewModel,
                            folder: child,
                            parentSource: parentSource,
                            depth: depth + 1,
                            isRoot: false,
                            expandedFolderPaths: $expandedFolderPaths
                        )
                    }
                }
                // Render photo leaf nodes for photos directly in this folder.
                if let photos = cachedPhotos, !photos.isEmpty {
                    ForEach(photos, id: \.id) { photoSet in
                        PhotoLeafNode(
                            viewModel: viewModel,
                            photoSet: photoSet,
                            parentFolder: folder,
                            parentSource: parentSource,
                            depth: depth + 1
                        )
                    }
                }
            } label: {
                row
            }
            .tint(Theme.Color.textSecondary)
            .onAppear {
                if expandedFolderPaths.contains(folder.path) {
                    ensureChildrenLoaded()
                }
            }
            .listRowBackground(
                RoundedRectangle(cornerRadius: Theme.Radius.m)
                    .fill(isSelected
                          ? Theme.Color.rowSelectedFill
                          : (isHovered ? Theme.Color.rowHoverFill : Color.clear))
                    .padding(.horizontal, Theme.Space.s8)
            )
        } else {
            row
                .listRowBackground(
                    RoundedRectangle(cornerRadius: Theme.Radius.m)
                        .fill(isSelected
                              ? Theme.Color.rowSelectedFill
                              : (isHovered ? Theme.Color.rowHoverFill : Color.clear))
                        .padding(.horizontal, Theme.Space.s8)
                )
        }
    }

    private var row: some View {
        HStack(spacing: Theme.Space.s6) {
            let iconName = iconNameForFolder(folder)
            let iconColor = iconColorForFolder(folder)

            Image(systemName: hasFailed ? "exclamationmark.triangle.fill" : iconName)
                .foregroundStyle(hasFailed ? Theme.Color.danger
                                           : (isSubtreeSelected ? Theme.Color.accent : iconColor))
                .font(.system(size: isRoot ? 14 : 12))
                .frame(width: 16)

            Text(displayName)
                .font(isRoot ? Theme.Font.subheadline : Theme.Font.caption)
                .foregroundStyle(hasFailed ? Theme.Color.danger
                                           : Theme.Color.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)

            if hasFailed {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Color.danger)
                    .help("Failed to read this source")
            }

            Spacer(minLength: 4)

            if photoCount > 0 {
                Text("\(photoCount)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(isSubtreeSelected ? Theme.Color.accent
                                                      : Theme.Color.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(
                            isSubtreeSelected
                            ? Theme.Color.accent.opacity(0.18)
                            : Theme.Color.overlaySoft
                        )
                    )
            }

            if isHovered {
                HStack(spacing: Theme.Space.s6) {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([folder])
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Color.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .help("Reveal in Finder")

                    if isRoot {
                        Button {
                            viewModel.removeSourceDirectory(folder)
                        } label: {
                            Image(systemName: "xmark.circle")
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Color.textSecondary)
                        }
                        .buttonStyle(.plain)
                        .help("Remove source folder")
                    }
                }
            }
        }
        .padding(.leading, isRoot ? 2 : 0)
        .padding(.trailing, Theme.Space.s10)
        .padding(.vertical, Theme.Space.s4)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovered = hovering }
        }
        .onTapGesture {
            toggleSelection()
        }
        .contextMenu {
            Button(isSubtreeSelected ? "Clear Filter" : "Filter to This Folder") {
                toggleSelection()
            }
            Divider()
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([folder])
            }
            if isRoot {
                Button("Remove Source Folder") {
                    viewModel.removeSourceDirectory(folder)
                }
            }
        }
    }

    private var hasDirectPhotos: Bool {
        if let cached = cachedPhotos {
            return !cached.isEmpty
        }
        return viewModel.hasPhotosDirectly(in: folder)
    }

    private var canExpand: Bool {
        if let cached = cachedChildren { return !cached.isEmpty }
        return photoCount > 0 || hasDirectPhotos
    }

    private func toggleSelection() {
        if isSubtreeSelected {
            viewModel.selectedSubfolderFilter = nil
        } else {
            viewModel.selectedSubfolderFilter = folder
        }
    }
}

struct PhotoLeafNode: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel
    let photoSet: PhotoSet
    let parentFolder: URL
    let parentSource: URL
    let depth: Int

    @State private var isHovered = false

    private var isFocused: Bool {
        viewModel.filteredPhotoSets.indices.contains(viewModel.focusedPhotoIndex) &&
        viewModel.filteredPhotoSets[viewModel.focusedPhotoIndex].id == photoSet.id
    }

    var body: some View {
        HStack(spacing: Theme.Space.s6) {
            Image(systemName: "camera.fill")
                .font(.system(size: 11, weight: .light))
                .foregroundStyle(
                    isFocused ? Theme.Color.accent :
                    colorForFormat(photoSet.formatLabel).opacity(0.7)
                )
                .frame(width: 16, height: 22)

            Text(photoSet.displayName)
                .font(Theme.Font.body)
                .foregroundStyle(isFocused ? Theme.Color.accent : Theme.Color.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            if !photoSet.formatLabel.isEmpty {
                Text(photoSet.formatLabel)
                    .font(Theme.Font.caption2)
                    .foregroundStyle(
                        isFocused ? Theme.Color.accent :
                        colorForFormat(photoSet.formatLabel).opacity(0.85)
                    )
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Theme.Color.overlaySoft)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
            }

            if photoSet.mediaFiles.count > 1 {
                Text("×\(photoSet.mediaFiles.count)")
                    .font(Theme.Font.caption2)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .padding(.trailing, Theme.Space.s4)
            }
        }
        .frame(height: 22)
        .padding(.leading, Theme.Space.s4)
        .padding(.trailing, Theme.Space.s10)
        .padding(.vertical, Theme.Space.s4)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovered = hovering }
        }
        .onTapGesture {
            selectPhoto()
        }
        .listRowBackground(
            RoundedRectangle(cornerRadius: Theme.Radius.m)
                .fill(isFocused
                      ? Theme.Color.rowSelectedFill
                      : (isHovered ? Theme.Color.rowHoverFill : Color.clear))
                .padding(.horizontal, Theme.Space.s8)
        )
    }

    private func selectPhoto() {
        viewModel.selectedSubfolderFilter = parentFolder
        if let idx = viewModel.filteredPhotoSets.firstIndex(where: { $0.id == photoSet.id }) {
            viewModel.focusedPhotoIndex = idx
        }
    }

    private func colorForFormat(_ label: String) -> Color {
        let upper = label.uppercased()
        if upper.contains("JPEG") { return Theme.Color.FileColor.jpeg }
        if upper.contains("HEIF") { return Theme.Color.FileColor.heif }
        if upper.contains("RAW")  { return Theme.Color.FileColor.raw }
        return Theme.Color.FileColor.other
    }
}


// MARK: - Active Tags Bar

struct ActiveTagsBar: View {
    let count: Int
    let isEmpty: Bool
    @Binding var isExpanded: Bool
    let onClear: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Theme.Space.s6) {
            HStack(spacing: Theme.Space.s6) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.Color.textSecondary)

                Image(systemName: isEmpty
                      ? "tag"
                      : "tag.fill")
                    .foregroundStyle(isEmpty ? Theme.Color.textTertiary : Theme.Color.accent)
                    .font(Theme.Font.subheadline)

                Text(isEmpty
                     ? "No active tags"
                     : "^[\(count) active tag](inflect: true)")
                    .font(Theme.Font.caption)
                    .foregroundStyle(isEmpty ? Theme.Color.textTertiary : Theme.Color.textPrimary)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.smooth(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }

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
                  ? "Select a tag in the list below to filter the grid."
                  : "Clear all active tag filters")
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
                            .foregroundStyle(viewModel.filterRule == rule ? Theme.Color.accent : Theme.Color.textSecondary)
                            .frame(width: 16)
                        Text(rule.rawValue)
                            .foregroundStyle(Theme.Color.textPrimary)
                        Spacer()
                        // Count badge
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
        case .allPhotos:
            return viewModel.cachedAllPhotosCount
        case .editedOnly:
            return viewModel.cachedEditedCount
        case .uneditedOnly:
            return viewModel.cachedUneditedCount
        }
    }
}

// MARK: - Active Tags Detail Section View

struct ActiveTagsDetailSectionView: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel
    @State private var hoveredTagID: UUID? = nil

    var body: some View {
        let activeTags = viewModel.tagStore.tags.filter { viewModel.selectedTagFilters.contains($0.id) }
        
        Section("ACTIVE TAGS") {
            if activeTags.isEmpty {
                Text("No active tags")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(activeTags) { tag in
                    Button {
                        _ = withAnimation(.smooth(duration: 0.15)) {
                            viewModel.selectedTagFilters.remove(tag.id)
                        }
                    } label: {
                        HStack(spacing: Theme.Space.s8) {
                            // Checkbox
                            Image(systemName: "checkmark.square.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.Color.accent)

                            // Tag color indicator
                            Circle()
                                .fill(tag.color)
                                .frame(width: 8, height: 8)

                            // Tag Name
                            Text(tag.name)
                                .font(Theme.Font.body)
                                .foregroundStyle(Theme.Color.textPrimary)

                            Spacer()

                            // Count of photos with this tag
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
                            .fill(hoveredTagID == tag.id ? Theme.Color.rowHoverFill : Color.clear)
                            .padding(.horizontal, Theme.Space.s8)
                    )
                }
            }
        }
    }
}
