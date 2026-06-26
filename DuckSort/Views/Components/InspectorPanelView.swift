//
//  InspectorPanelView.swift
//  DuckSort
//

import SwiftUI

struct InspectorPanelView: View {
    let metadata: MetadataSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s12) {
            Text("Info")
                .font(Theme.Font.headline)
                .padding(.bottom, Theme.Space.s4)

            HStack(spacing: Theme.Space.s12) {
                Image(systemName: "camera.aperture")
                    .font(.title2)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(metadata.cameraModel ?? "Unknown Camera")
                        .font(Theme.Font.subheadline)
                    Text(metadata.lensModel ?? "Unknown Lens")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Color.textSecondary)
                }
            }
            .padding(.bottom, Theme.Space.s6)

            Grid(alignment: .leading, horizontalSpacing: Theme.Space.s16, verticalSpacing: Theme.Space.s8) {
                GridRow {
                    Text("Aperture").foregroundStyle(Theme.Color.textSecondary)
                    Text(formatAperture(metadata.aperture))
                }
                GridRow {
                    Text("Shutter").foregroundStyle(Theme.Color.textSecondary)
                    Text(formatShutter(metadata.shutterSpeed))
                }
                GridRow {
                    Text("ISO").foregroundStyle(Theme.Color.textSecondary)
                    Text(formatISO(metadata.iso))
                }
            }
            .font(Theme.Font.subheadline)
        }
        .padding(Theme.Space.s16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.85))
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xl))
        .shadow(color: Theme.Color.overlayScrim, radius: 8, y: 4)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.xl)
                .stroke(Theme.Color.overlaySofter, lineWidth: Theme.Stroke.hairline)
        )
    }

    private func formatAperture(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "f/%.1f", value)
    }

    private func formatShutter(_ value: Double?) -> String {
        guard let value = value, value > 0 else { return "--" }
        if value >= 1 {
            return String(format: "%.1fs", value)
        } else {
            return String(format: "1/%d", Int(round(1.0 / value)))
        }
    }

    private func formatISO(_ value: Int?) -> String {
        guard let value else { return "--" }
        return "\(value)"
    }
}