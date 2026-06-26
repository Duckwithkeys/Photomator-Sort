//
//  TransferFooter.swift
//  DuckSort
//

import SwiftUI

struct TransferFooter: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel
    @State private var isDestHovered = false
    @State private var hoveredOp: RoutedOperation? = nil

    var body: some View {
        VStack(spacing: Theme.Space.s10) {
            HStack(spacing: Theme.Space.s16) {
                statusBlock
                Spacer(minLength: Theme.Space.s16)
                ruleSummary
                Spacer(minLength: Theme.Space.s16)
                actionsBlock
            }
            .padding(.horizontal, Theme.Space.s16)
            .padding(.vertical, Theme.Space.s12)

            if let progress = viewModel.operationProgress {
                progressBlock(progress)
            }
        }
        .background(Theme.Color.footerBackground)
        .overlay(Divider(), alignment: .top)
    }

    private var statusBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s4) {
            Text(viewModel.statusMessage)
                .font(Theme.Font.callout)
                .lineLimit(1)

            HStack(spacing: Theme.Space.s6) {
                if let focused = viewModel.currentFocusedPhotoSet {
                    HStack(spacing: 4) {
                        Image(systemName: "scope")
                            .font(Theme.Font.caption2)
                        Text("Focus: \(focused.baseName)")
                            .font(Theme.Font.caption)
                            .lineLimit(1)
                    }
                    .foregroundStyle(Theme.Color.accent)
                }

                if viewModel.selectedCount > 0 {
                    Text("·")
                        .foregroundStyle(Theme.Color.textSecondary)
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(Theme.Font.caption2)
                            .foregroundStyle(Theme.Color.success)
                        Text("^[\(viewModel.selectedCount) photo set](inflect: true) selected · \(viewModel.selectedFileCount) files")
                            .font(Theme.Font.caption)
                    }
                    .foregroundStyle(Theme.Color.textSecondary)

                    Button {
                        viewModel.clearSelection()
                    } label: {
                        Text("Clear")
                            .font(Theme.Font.caption2)
                            .underline()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.Color.textSecondary)
                }
            }
        }
    }

    private var actionsBlock: some View {
        HStack(spacing: Theme.Space.s8) {
            destinationButton
            ForEach(RoutedOperation.allCases) { op in
                actionButton(op)
            }
            if viewModel.isTransferring {
                ProgressView().controlSize(.small)
            }
        }
    }

    private var destinationButton: some View {
        Button {
            viewModel.chooseDestinationDirectory()
        } label: {
            HStack(spacing: Theme.Space.s6) {
                Image(systemName: "tray.and.arrow.down")
                    .foregroundStyle(Theme.Color.accent)
                if let dest = viewModel.destinationDirectory {
                    Text("Destination: \(Text(dest.lastPathComponent).foregroundStyle(Theme.Color.textPrimary))")
                        .font(Theme.Font.callout)
                        .foregroundStyle(Theme.Color.textSecondary)
                } else {
                    Text("Choose Destination…")
                        .font(Theme.Font.callout)
                        .foregroundStyle(Theme.Color.textPrimary)
                }
            }
            .padding(.horizontal, Theme.Space.s10)
            .padding(.vertical, Theme.Space.s6)
            .flatSidebarButton(isHovered: isDestHovered)
        }
        .buttonStyle(.plain)
        .onHover { isDestHovered = $0 }
    }

    private func actionButton(_ op: RoutedOperation) -> some View {
        Button {
            viewModel.performRoutedOperation(op)
        } label: {
            HStack(spacing: Theme.Space.s6) {
                Image(systemName: op.systemImage)
                    .font(Theme.Font.callout)
                    .foregroundStyle(Theme.Color.accent)
                Text(op.displayName)
                    .font(Theme.Font.callout)
                    .foregroundStyle(Theme.Color.textPrimary)
            }
            .padding(.horizontal, Theme.Space.s10)
            .padding(.vertical, Theme.Space.s6)
            .flatSidebarButton(isHovered: hoveredOp == op)
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.canTransfer)
        .onHover { isHovered in hoveredOp = isHovered ? op : nil }
    }

    @ViewBuilder
    private var ruleSummary: some View {
        if let rule = viewModel.ruleStore.selectedRule {
            HStack(spacing: Theme.Space.s6) {
                Image(systemName: "folder.badge.gearshape")
                    .foregroundStyle(Theme.Color.textSecondary)
                Text("Rule:")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.textSecondary)
                Text(rule.name)
                    .font(Theme.Font.caption)
                Divider().frame(height: 12)
                Text(ExportPathRouter.describe(rule.components) {
                    viewModel.tagStore.categoryName(id: $0)
                })
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
            }
            .padding(.horizontal, Theme.Space.s10)
            .padding(.vertical, Theme.Space.s4)
            .background(Theme.Color.cellBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.m))
        } else {
            HStack(spacing: Theme.Space.s6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.Color.warning)
                Text("No routing rule selected — open the Routing Rules editor to create one.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.textSecondary)
            }
        }
    }

    private func progressBlock(_ progress: FileOperationProgress) -> some View {
        VStack(spacing: Theme.Space.s6) {
            if progress.totalBytes > 0 {
                ProgressView(value: Double(progress.completedBytes), total: Double(progress.totalBytes))
                    .tint(Theme.Color.accent)
                HStack {
                    Text("\(formatBytes(progress.completedBytes)) of \(formatBytes(progress.totalBytes))")
                    Spacer()
                    Text("\(progress.completed) / \(progress.total) files")
                    Spacer()
                    Text("\(formatBytes(Int64(progress.bytesPerSecond)))/s")
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.Color.textSecondary)
            } else {
                ProgressView(value: Double(progress.completed), total: Double(max(1, progress.total)))
                    .tint(Theme.Color.accent)
                Text("\(progress.completed) of \(progress.total) files")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.Color.textSecondary)
            }
        }
        .padding(.horizontal, Theme.Space.s16)
        .padding(.bottom, Theme.Space.s10)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: max(0, bytes))
    }
}
