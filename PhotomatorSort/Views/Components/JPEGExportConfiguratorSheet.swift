//
//  JPEGExportConfiguratorSheet.swift
//  PhotomatorSort
//

import SwiftUI

struct JPEGExportConfiguratorSheet: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("JPEG Export Configurator", systemImage: "photo.on.rectangle.angled")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Settings Section
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Export Settings")
                            .font(.headline)

                        // Naming Preset Selector
                        VStack(alignment: .leading, spacing: 6) {
                            Text("File Naming Preset")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                            
                            Picker("Naming Preset", selection: $viewModel.namingPreset) {
                                ForEach(ExportNamingPreset.allCases) { preset in
                                    Text(preset.rawValue).tag(preset)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .frame(maxWidth: .infinity)
                        }

                        // Jpeg Quality Slider
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("JPEG Compression Quality")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(String(format: "%.0f%%", viewModel.jpegQuality * 100))
                                    .font(.subheadline.weight(.semibold))
                                    .monospacedDigit()
                            }
                            
                            Slider(value: $viewModel.jpegQuality, in: 0.1...1.0, step: 0.05)
                            
                            Text("Recommended: 90% – 95% for optimal quality and size.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(8)

                    // Destination Preview Section
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Preview Export Path")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Image(systemName: "folder.fill")
                                    .foregroundStyle(.secondary)
                                Text(previewFolderPath)
                                    .font(.caption.monospaced())
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .foregroundStyle(.secondary)
                            }

                            HStack(spacing: 8) {
                                Image(systemName: "doc.fill")
                                    .foregroundStyle(Color.accentColor)
                                Text(previewFileName)
                                    .font(.body.weight(.semibold))
                                    .lineLimit(1)
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.08))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                        )
                    }

                    Spacer()
                }
                .padding(20)
            }

            Divider()

            // Footer / Action Button
            HStack {
                Spacer()
                Button {
                    dismiss()
                    viewModel.performRoutedOperation(.exportJPEGs)
                } label: {
                    Label("Export \(viewModel.selectedCount) JPEGs", systemImage: "arrow.down.doc.fill")
                        .font(.body.weight(.semibold))
                        .padding(.vertical, 4)
                        .padding(.horizontal, 12)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(viewModel.selectedCount == 0 || viewModel.destinationDirectory == nil)
            }
            .padding()
        }
        .frame(width: 480, height: 420)
    }

    // MARK: - Live Preview Helpers

    private var previewFolderPath: String {
        guard let firstPhoto = viewModel.selectedPhotoSets.first,
              let rule = viewModel.ruleStore.selectedRule,
              let dest = viewModel.destinationDirectory
        else {
            return "Select destination folder to preview"
        }

        let meta = viewModel.metadata(for: firstPhoto)
        let tags = viewModel.assignedTags(for: firstPhoto)

        let folders = ExportPathRouter.destinationFolders(
            base: dest,
            rule: rule.components,
            metadata: meta,
            assignedTags: tags
        ) {
            viewModel.tagStore.categoryName(id: $0)
        }
        return folders.map(\.path).joined(separator: ", ")
    }

    private var previewFileName: String {
        guard let firstPhoto = viewModel.selectedPhotoSets.first else {
            return "No photos selected"
        }
        let meta = viewModel.metadata(for: firstPhoto)

        let parts = viewModel.namingPreset.tokens.map { token -> String in
            switch token {
            case .originalName:
                return firstPhoto.baseName
            case .captureDate:
                return Self.dateFileName(for: meta.captureDate)
            case .sequence:
                return "0001"
            case .cameraModel:
                return FilenameSanitizer.clean(meta.cameraModel ?? "", fallback: "Unknown Camera")
            case .lensModel:
                return FilenameSanitizer.clean(meta.lensModel ?? "", fallback: "Unknown Lens")
            }
        }
        return FilenameSanitizer.clean(parts.joined(separator: "_")) + ".jpg"
    }

    private static func dateFileName(for date: Date?) -> String {
        guard let date else { return "Unknown-Date" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: date)
    }
}
