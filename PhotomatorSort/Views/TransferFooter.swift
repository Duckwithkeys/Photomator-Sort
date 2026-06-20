//
//  TransferFooter.swift
//  PhotomatorSort
//

import SwiftUI

struct TransferFooter: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel
    @State private var showExportConfigurator = false
    @State private var isDestHovered = false
    @State private var hoveredOp: RoutedOperation? = nil

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(viewModel.statusMessage)
                        .font(.callout)
                        .lineLimit(1)

                    Text("\(viewModel.selectedCount) photo sets selected, \(viewModel.selectedFileCount) files")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    viewModel.chooseDestinationDirectory()
                } label: {
                    Label(viewModel.destinationDirectory?.lastPathComponent ?? "Choose Destination", systemImage: "tray.and.arrow.down")
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .liquidGlassButton(isHovered: isDestHovered)
                }
                .buttonStyle(.plain)
                .onHover { isDestHovered = $0 }

                if viewModel.isTransferring {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            HStack(spacing: 10) {
                ruleSummary

                Spacer()

                ForEach(RoutedOperation.allCases) { op in
                    Button {
                        if op == .exportJPEGs {
                            showExportConfigurator = true
                        } else {
                            viewModel.performRoutedOperation(op)
                        }
                    } label: {
                        Label(op.displayName, systemImage: op.systemImage)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .liquidGlassButton(isHovered: hoveredOp == op)
                    }
                    .buttonStyle(.plain)
                    .disabled(!viewModel.canTransfer)
                    .onHover { isHovered in
                        hoveredOp = isHovered ? op : nil
                    }
                }
            }

            if let progress = viewModel.operationProgress {
                VStack(spacing: 6) {
                    if progress.totalBytes > 0 {
                        ProgressView(value: Double(progress.completedBytes), total: Double(progress.totalBytes))
                            .tint(.accentColor)
                        
                        HStack {
                            Text("\(formatBytes(progress.completedBytes)) of \(formatBytes(progress.totalBytes))")
                            Spacer()
                            Text("\(progress.completed) / \(progress.total) files")
                            Spacer()
                            Text("\(formatBytes(Int64(progress.bytesPerSecond)))/s")
                        }
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    } else {
                        ProgressView(value: Double(progress.completed), total: Double(max(1, progress.total)))
                            .tint(.accentColor)
                        Text("\(progress.completed) of \(progress.total) files")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .liquidGlassPanel()
        .sheet(isPresented: $showExportConfigurator) {
            JPEGExportConfiguratorSheet(viewModel: viewModel)
        }
    }

    @ViewBuilder
    private var ruleSummary: some View {
        if let rule = viewModel.ruleStore.selectedRule {
            HStack(spacing: 6) {
                Image(systemName: "folder.badge.gearshape")
                    .foregroundStyle(.secondary)
                Text("Rule:")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(rule.name)
                    .font(.caption.weight(.medium))
                Text("•")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(ExportPathRouter.describe(rule.components) {
                    viewModel.tagStore.categoryName(id: $0)
                })
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
        } else {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("No routing rule selected — open the Routing Rules editor to create one.")
                    .font(.caption)
            }
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: max(0, bytes))
    }
}
