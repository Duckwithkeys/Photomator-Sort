//
//  PreFlightVisualizerView.swift
//  DuckSort
//
//  A native split-pane dry-run visualizer displaying the simulated folder structures
//  and destination path collision auto-resolutions before executing the transfer.
//

import SwiftUI

struct PreFlightVisualizerView: View {
    let plan: RoutedPlan
    @ObservedObject var viewModel: PhotoLibraryViewModel
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @State private var rootNode = SimulatedFolderTree.Node(name: "", url: URL(fileURLWithPath: "/"))
    @State private var isSimulating = true
    @State private var summaryStats = SummaryStats()
    @State private var collapsedFolders: Set<URL> = []

    struct SummaryStats {
        var totalFiles = 0
        var foldersCreated = 0
        var newFilesCount = 0
        var skipsCount = 0
        var overwritesCount = 0
        var renamesCount = 0
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            headerView
                .padding(.horizontal, Theme.Space.s24)
                .padding(.top, Theme.Space.s24)
                .padding(.bottom, Theme.Space.s16)

            Divider()
                .background(Theme.Color.separator)

            if isSimulating {
                simulatingView
            } else {
                splitPaneView
            }

            Divider()
                .background(Theme.Color.separator)

            // Footer Action Bar
            footerView
                .padding(.horizontal, Theme.Space.s24)
                .padding(.vertical, Theme.Space.s16)
                .background(Theme.Color.footerBackground)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Color.background)
        .task {
            await runSimulation()
        }
    }

    // MARK: - Subviews

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: Theme.Space.s4) {
                Text("Pre-Flight Smart Routing Visualizer")
                    .font(Theme.Font.title)
                    .foregroundStyle(Theme.Color.textPrimary)
                Text("Dry-run preview for \(plan.operation.displayName.lowercased()) to \(plan.baseDestination.lastPathComponent)")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            Spacer()
            
            if !isSimulating {
                HStack(spacing: Theme.Space.s12) {
                    statBadge(label: "New", count: summaryStats.newFilesCount, color: Theme.Color.success)
                    statBadge(label: "Rename", count: summaryStats.renamesCount, color: Theme.Color.accent)
                    statBadge(label: "Overwrite", count: summaryStats.overwritesCount, color: Theme.Color.warning)
                    statBadge(label: "Skip", count: summaryStats.skipsCount, color: Theme.Color.textTertiary)
                }
            }
        }
    }

    private func statBadge(label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(Theme.Font.monoCaption)
                .foregroundStyle(Theme.Color.textSecondary)
            Text("\(count)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.Color.textPrimary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.12), in: Capsule())
    }

    private var simulatingView: some View {
        VStack(spacing: Theme.Space.s16) {
            Spacer()
            ProgressView("Simulating directory operations...")
                .tint(.white)
            Text("Evaluating path routing rules and validating target checksums...")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Color.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var splitPaneView: some View {
        HSplitView {
            // Left Pane: Source Selection List
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("SOURCE PHOTO SETS (\(plan.photos.count))")
                        .font(Theme.Font.caption2)
                        .foregroundStyle(Theme.Color.textSecondary)
                    Spacer()
                }
                .padding(.horizontal, Theme.Space.s16)
                .padding(.vertical, Theme.Space.s12)
                .background(Theme.Color.sidebarBackground)

                List(plan.photos, id: \.photoSet.id) { photo in
                    HStack {
                        Image(systemName: "photo.stack")
                            .foregroundStyle(Theme.Color.textSecondary)
                        Text(photo.photoSet.baseName)
                            .font(Theme.Font.bodyBold)
                            .foregroundStyle(Theme.Color.textPrimary)
                        Spacer()
                        Text("\(photo.photoSet.allFiles.count) files")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Color.textTertiary)
                    }
                    .listRowBackground(Color.clear)
                }
                .scrollContentBackground(.hidden)
            }
            .frame(minWidth: 250, idealWidth: 300, maxWidth: 350)

            // Right Pane: Target Structural Tree View
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("SIMULATED TARGET DIRECTORY HIERARCHY")
                        .font(Theme.Font.caption2)
                        .foregroundStyle(Theme.Color.textSecondary)
                    Spacer()
                }
                .padding(.horizontal, Theme.Space.s16)
                .padding(.vertical, Theme.Space.s12)
                .background(Theme.Color.sidebarBackground)

                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.s12) {
                        SimulatedFolderNodeView(node: rootNode, collapsedFolders: $collapsedFolders)
                    }
                    .padding(Theme.Space.s16)
                }
                .scrollContentBackground(.hidden)
            }
            .frame(minWidth: 450, idealWidth: 500, maxWidth: .infinity)
        }
    }

    private var footerView: some View {
        HStack {
            Button(action: onCancel) {
                Text("Cancel")
                    .padding(.horizontal, Theme.Space.s16)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            
            Spacer()
            
            Button(action: onConfirm) {
                HStack(spacing: Theme.Space.s6) {
                    Image(systemName: plan.operation.systemImage)
                    Text(plan.operation.displayName)
                }
                .padding(.horizontal, Theme.Space.s16)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.Color.accent)
        }
    }

    // MARK: - Simulation Engine

    private func runSimulation() async {
        let categoryNames = Dictionary(
            uniqueKeysWithValues: viewModel.tagStore.categories.map { ($0.id, $0.name) }
        )
        let categoryNameProvider: (UUID) -> String? = { id in
            categoryNames[id]
        }

        // Run simulation in background
        let results = await Task.detached(priority: .userInitiated) {
            let tree = SimulatedFolderTree(baseDestination: plan.baseDestination)
            var stats = SummaryStats()

            for routed in plan.photos {
                let folders = ExportPathRouter.destinationFolders(
                    base: plan.baseDestination,
                    rule: plan.rule,
                    metadata: routed.metadata,
                    assignedTags: routed.tags,
                    categoryNameProvider: categoryNameProvider
                )
                
                for folder in folders {
                    for fileURL in routed.photoSet.allFiles {
                        let resolution = CollisionResolver.resolve(
                            source: fileURL,
                            destinationDir: folder,
                            fileManager: .default
                        )
                        
                        let destURL: URL
                        switch resolution {
                        case .skip:
                            destURL = folder.appendingPathComponent(fileURL.lastPathComponent)
                            stats.skipsCount += 1
                        case .overwrite:
                            destURL = folder.appendingPathComponent(fileURL.lastPathComponent)
                            stats.overwritesCount += 1
                        case .rename(let uniqueURL):
                            destURL = uniqueURL
                            stats.renamesCount += 1
                        case .normal(let destURLVal):
                            destURL = destURLVal
                            stats.newFilesCount += 1
                        }
                        
                        stats.totalFiles += 1
                        
                        let file = SimulatedFile(
                            sourceURL: fileURL,
                            destinationURL: destURL,
                            resolution: resolution
                        )
                        tree.insert(file: file, relativeTo: plan.baseDestination)
                    }
                }
            }

            tree.sortTree()
            stats.foldersCreated = tree.countFolders()

            return (tree.root, stats)
        }.value

        self.rootNode = results.0
        self.summaryStats = results.1
        self.isSimulating = false
    }
}

// MARK: - Recursive Folder Node View

struct SimulatedFolderNodeView: View {
    let node: SimulatedFolderTree.Node
    @Binding var collapsedFolders: Set<URL>

    private var isExpanded: Binding<Bool> {
        Binding(
            get: { !collapsedFolders.contains(node.url) },
            set: { expand in
                withAnimation(.smooth(duration: 0.15)) {
                    if expand {
                        collapsedFolders.remove(node.url)
                    } else {
                        collapsedFolders.insert(node.url)
                    }
                }
            }
        )
    }

    var body: some View {
        DisclosureGroup(isExpanded: isExpanded) {
            VStack(alignment: .leading, spacing: Theme.Space.s6) {
                // Subfolders first
                ForEach(node.childFolders) { child in
                    SimulatedFolderNodeView(node: child, collapsedFolders: $collapsedFolders)
                }

                // Subfiles next
                ForEach(node.files) { file in
                    HStack(spacing: Theme.Space.s10) {
                        Image(systemName: "doc")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Color.textSecondary)
                        
                        Text(file.sourceURL.lastPathComponent)
                            .font(Theme.Font.monoCaption)
                            .foregroundStyle(Theme.Color.textPrimary)
                        
                        Spacer()
                        
                        if case .rename(let uniqueURL) = file.resolution {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.right")
                                    .font(Theme.Font.caption2)
                                    .foregroundStyle(Theme.Color.textTertiary)
                                Text(uniqueURL.lastPathComponent)
                                    .font(Theme.Font.monoCaption)
                                    .foregroundStyle(Theme.Color.accent)
                            }
                        }

                        resolutionPill(for: file.resolution)
                    }
                    .padding(.vertical, 3)
                    .padding(.leading, 6)
                }
            }
            .padding(.leading, 12)
            .padding(.vertical, Theme.Space.s6)
        } label: {
            HStack(spacing: Theme.Space.s6) {
                Image(systemName: "folder")
                    .foregroundStyle(Theme.Color.accent)
                    .font(.system(size: 11))
                
                Text(node.name)
                    .font(Theme.Font.bodyBold)
                    .foregroundStyle(Theme.Color.textPrimary)
                
                Spacer()
                
                Text("\(node.totalFilesCount) files")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.Color.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(Theme.Color.overlaySoft)
                    )
            }
            .padding(.vertical, 4)
        }
        .tint(Theme.Color.textSecondary)
    }

    private func resolutionPill(for resolution: CollisionResolution) -> some View {
        let text = resolution.label
        let color: Color
        switch resolution {
        case .normal:    color = Theme.Color.success
        case .rename:    color = Theme.Color.accent
        case .overwrite: color = Theme.Color.warning
        case .skip:      color = Theme.Color.textTertiary
        }

        return Text(text)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(Theme.Color.textInverse)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color, in: RoundedRectangle(cornerRadius: Theme.Radius.s))
    }
}

// MARK: - Simulation Structures

class SimulatedFolderTree {
    class Node: Identifiable {
        let id = UUID()
        let name: String
        let url: URL
        var childFolders: [Node] = []
        var files: [SimulatedFile] = []
        
        init(name: String, url: URL) {
            self.name = name
            self.url = url
        }
        
        var totalFilesCount: Int {
            return files.count + childFolders.reduce(0) { $0 + $1.totalFilesCount }
        }
    }
    
    let root: Node
    
    init(baseDestination: URL) {
        self.root = Node(name: baseDestination.lastPathComponent, url: baseDestination.standardizedFileURL)
    }
    
    func insert(file: SimulatedFile, relativeTo base: URL) {
        let basePath = base.standardizedFileURL.path
        let destPath = file.destinationURL.deletingLastPathComponent().standardizedFileURL.path
        
        guard destPath.hasPrefix(basePath) else {
            root.files.append(file)
            return
        }
        
        let relativeString = String(destPath.dropFirst(basePath.count))
        let components = relativeString.components(separatedBy: "/").filter { !$0.isEmpty }
        
        var current = root
        var currentURL = base.standardizedFileURL
        
        for comp in components {
            currentURL = currentURL.appendingPathComponent(comp)
            if let existing = current.childFolders.first(where: { $0.name == comp }) {
                current = existing
            } else {
                let newNode = Node(name: comp, url: currentURL)
                current.childFolders.append(newNode)
                current = newNode
            }
        }
        
        current.files.append(file)
    }
    
    func sortTree() {
        func sortNode(_ node: Node) {
            node.childFolders.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            node.files.sort { $0.destinationURL.lastPathComponent.localizedStandardCompare($1.destinationURL.lastPathComponent) == .orderedAscending }
            for child in node.childFolders {
                sortNode(child)
            }
        }
        sortNode(root)
    }
    
    func countFolders() -> Int {
        func count(node: Node) -> Int {
            return node.childFolders.count + node.childFolders.reduce(0) { $0 + count(node: $1) }
        }
        return count(node: root)
    }
}

struct SimulatedFile: Identifiable {
    let id = UUID()
    let sourceURL: URL
    let destinationURL: URL
    let resolution: CollisionResolution
}
