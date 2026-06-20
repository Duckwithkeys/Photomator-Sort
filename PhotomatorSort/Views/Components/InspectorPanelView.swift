//
//  InspectorPanelView.swift
//  PhotomatorSort
//

import SwiftUI

struct InspectorPanelView: View {
    let metadata: MetadataSnapshot
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Info")
                .font(.headline)
                .padding(.bottom, 4)
            
            HStack(spacing: 12) {
                Image(systemName: "camera.aperture")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(metadata.cameraModel ?? "Unknown Camera")
                        .font(.subheadline.weight(.medium))
                    Text(metadata.lensModel ?? "Unknown Lens")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 6)
            
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text("Aperture")
                        .foregroundStyle(.secondary)
                    Text(formatAperture(metadata.aperture))
                }
                GridRow {
                    Text("Shutter")
                        .foregroundStyle(.secondary)
                    Text(formatShutter(metadata.shutterSpeed))
                }
                GridRow {
                    Text("ISO")
                        .foregroundStyle(.secondary)
                    Text(formatISO(metadata.iso))
                }
            }
            .font(.subheadline)
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.85))
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .frame(width: 240)
    }
    
    private func formatAperture(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "f/%.1f", value)
    }
    
    private func formatShutter(_ value: Double?) -> String {
        guard let value else { return "--" }
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
