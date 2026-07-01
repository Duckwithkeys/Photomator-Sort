//
//  InsightsView.swift
//  DuckSort
//
//  Camera & Lens Performance Insights dashboard.
//  Uses SwiftUI Canvas/GeometryReader for charts — no Charts framework.
//

import SwiftUI

// MARK: - Data models

struct InsightBucket: Identifiable {
    let id = UUID()
    let label: String
    let count: Int
    let percentage: Double // 0.0-1.0
}

struct GearCombo: Identifiable {
    let id = UUID()
    let camera: String
    let lens: String
    let totalShots: Int
    let pickRatio: Double  // 0.0-1.0, pick==1 is a flagged pick
    let avgAperture: Double?
}

struct InsightReport {
    let totalPhotos: Int
    let uniqueCameras: Int
    let uniqueLenses: Int
    let earliestDate: Date?
    let latestDate: Date?
    let focalLengthBuckets: [InsightBucket]
    let apertureBuckets: [InsightBucket]
    let isoBuckets: [InsightBucket]
    let shutterBuckets: [InsightBucket]
    let topGearCombos: [GearCombo]

    var isEmpty: Bool { totalPhotos == 0 }
}

// MARK: - Main View

struct InsightsView: View {
    let report: InsightReport
    let onDismiss: () -> Void

    @State private var animating = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        ZStack {
            Theme.Color.background.ignoresSafeArea()

            if report.isEmpty {
                VStack(spacing: 0) {
                    headerBar
                    emptyState
                }
            } else {
                VStack(spacing: 0) {
                    headerBar
                    
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: Theme.Space.s24) {
                            summaryPills
                            chartsGrid
                            topGearSection
                        }
                        .padding(.horizontal, Theme.Space.s24)
                        .padding(.bottom, Theme.Space.s24)
                    }
                }
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                animating = true
            }
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(alignment: .center, spacing: Theme.Space.s12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("EXIF Analytics")
                    .font(Theme.Font.title)
                    .foregroundStyle(Theme.Color.textPrimary)
                Text("Camera & Lens Performance Insights")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            Spacer()
            Button(action: onDismiss) {
                ZStack {
                    Circle()
                        .fill(Theme.Color.overlaySoft)
                        .frame(width: 28, height: 28)
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.Color.textSecondary)
                }
            }
            .buttonStyle(.plain)
            .help("Close Insights")
        }
        .padding(.horizontal, Theme.Space.s24)
        .padding(.vertical, Theme.Space.s16)
    
        
                
        
    }

    // MARK: - Summary pills

    private var summaryPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Space.s12) {
                summaryPill(
                    icon: "photo.stack",
                    value: "\(report.totalPhotos)",
                    label: "Total Photos"
                )
                summaryPill(
                    icon: "camera",
                    value: "\(report.uniqueCameras)",
                    label: report.uniqueCameras == 1 ? "Camera" : "Cameras"
                )
                summaryPill(
                    icon: "camera.aperture",
                    value: "\(report.uniqueLenses)",
                    label: report.uniqueLenses == 1 ? "Lens" : "Lenses"
                )
                if let earliest = report.earliestDate, let latest = report.latestDate {
                    if Calendar.current.isDate(earliest, inSameDayAs: latest) {
                        summaryPill(
                            icon: "calendar",
                            value: Self.dateFormatter.string(from: earliest),
                            label: "Date"
                        )
                    } else {
                        summaryPill(
                            icon: "calendar",
                            value: "\(Self.dateFormatter.string(from: earliest)) – \(Self.dateFormatter.string(from: latest))",
                            label: "Date Range"
                        )
                    }
                }
            }
        }
    }

    private func summaryPill(icon: String, value: String, label: String) -> some View {
        HStack(spacing: Theme.Space.s8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.Color.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(Theme.Font.bodyBold)
                    .foregroundStyle(Theme.Color.textPrimary)
                Text(label)
                    .font(Theme.Font.caption2)
                    .foregroundStyle(Theme.Color.textSecondary)
            }
        }
        .padding(.horizontal, Theme.Space.s16)
        .padding(.vertical, Theme.Space.s12)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.xl)
                .fill(Theme.Color.sidebarBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.xl)
                        .strokeBorder(Theme.Color.separator, lineWidth: 1)
                )
        )
    }

    // MARK: - 2×2 Charts Grid

    private var chartsGrid: some View {
        // Two columns
        HStack(alignment: .top, spacing: Theme.Space.s16) {
            VStack(spacing: Theme.Space.s16) {
                chartCard(title: "FOCAL LENGTH", buckets: report.focalLengthBuckets)
                chartCard(title: "ISO DISTRIBUTION", buckets: report.isoBuckets)
            }
            VStack(spacing: Theme.Space.s16) {
                chartCard(title: "APERTURE", buckets: report.apertureBuckets)
                chartCard(title: "SHUTTER SPEED", buckets: report.shutterBuckets)
            }
        }
    }

    private func chartCard(title: String, buckets: [InsightBucket]) -> some View {
        let maxCount = buckets.map(\.count).max() ?? 1
        return VStack(alignment: .leading, spacing: Theme.Space.s12) {
            // Section header
            Text(title)
                .font(Theme.Font.caption2)
                .foregroundStyle(Theme.Color.textSecondary)
                .tracking(0.8)

            // Bars
            VStack(spacing: Theme.Space.s8) {
                ForEach(buckets) { bucket in
                    HorizontalBar(
                        bucket: bucket,
                        maxCount: maxCount,
                        animating: animating
                    )
                }
            }
        }
        .padding(Theme.Space.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.xl)
                .fill(Theme.Color.sidebarBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.xl)
                        .strokeBorder(Theme.Color.separator, lineWidth: 1)
                )
        )
    }

    // MARK: - Top Gear section

    private var topGearSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s12) {
            Text("TOP GEAR COMBINATIONS")
                .font(Theme.Font.caption2)
                .foregroundStyle(Theme.Color.textSecondary)
                .tracking(0.8)

            if report.topGearCombos.isEmpty {
                Text("No complete camera+lens data available")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .padding(Theme.Space.s16)
            } else {
                VStack(spacing: Theme.Space.s8) {
                    ForEach(Array(report.topGearCombos.prefix(8).enumerated()), id: \.offset) { index, combo in
                        GearComboRow(rank: index + 1, combo: combo, animating: animating)
                    }
                }
            }
        }
        .padding(Theme.Space.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.xl)
                .fill(Theme.Color.sidebarBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.xl)
                        .strokeBorder(Theme.Color.separator, lineWidth: 1)
                )
        )
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: Theme.Space.s16) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 52, weight: .thin))
                .foregroundStyle(Theme.Color.textTertiary)
            Text("No data available")
                .font(Theme.Font.headline)
                .foregroundStyle(Theme.Color.textSecondary)
            Text("Load a source folder to begin")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Color.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Horizontal Bar Component

private struct HorizontalBar: View {
    let bucket: InsightBucket
    let maxCount: Int
    let animating: Bool

    var body: some View {
        HStack(spacing: Theme.Space.s8) {
            // Label
            Text(bucket.label)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.textSecondary)
                .frame(width: 90, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            // Bar
            GeometryReader { geo in
                let fullWidth = geo.size.width
                let targetWidth = maxCount > 0
                    ? fullWidth * CGFloat(bucket.count) / CGFloat(maxCount)
                    : 0
                let animWidth = animating ? max(targetWidth, bucket.count > 0 ? 4 : 0) : 0

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Theme.Color.accent, Theme.Color.accent.opacity(0.6)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: animWidth, height: 10)
                    .animation(
                        .spring(response: 0.55, dampingFraction: 0.78),
                        value: animating
                    )
            }
            .frame(height: 10)

            // Count + percentage
            HStack(spacing: 4) {
                Text("\(bucket.count)")
                    .font(Theme.Font.monoCaption)
                    .foregroundStyle(Theme.Color.textPrimary)
                Text(String(format: "%.0f%%", bucket.percentage * 100))
                    .font(Theme.Font.monoCaption)
                    .foregroundStyle(Theme.Color.textTertiary)
            }
            .frame(width: 60, alignment: .trailing)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Gear Combo Row

private struct GearComboRow: View {
    let rank: Int
    let combo: GearCombo
    let animating: Bool

    private var rankColor: Color {
        switch rank {
        case 1: return Color(red: 1.0, green: 0.84, blue: 0.0)   // gold
        case 2: return Color(red: 0.75, green: 0.75, blue: 0.75) // silver
        case 3: return Color(red: 0.80, green: 0.50, blue: 0.20) // bronze
        default: return Theme.Color.textTertiary
        }
    }

    private var apertureString: String {
        guard let ap = combo.avgAperture else { return "—" }
        return String(format: "f/%.1f", ap)
    }

    var body: some View {
        VStack(spacing: Theme.Space.s6) {
            HStack(alignment: .top, spacing: Theme.Space.s12) {
                // Rank badge
                ZStack {
                    Circle()
                        .fill(rankColor.opacity(0.15))
                        .frame(width: 28, height: 28)
                    Text("\(rank)")
                        .font(Theme.Font.bodyBold)
                        .foregroundStyle(rankColor)
                }

                // Camera + Lens
                VStack(alignment: .leading, spacing: 2) {
                    Text(combo.camera)
                        .font(Theme.Font.bodyBold)
                        .foregroundStyle(Theme.Color.textPrimary)
                        .lineLimit(1)
                    Text(combo.lens)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Color.textSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Stats
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: Theme.Space.s4) {
                        Text("\(combo.totalShots)")
                            .font(Theme.Font.monoCaption)
                            .foregroundStyle(Theme.Color.textPrimary)
                        Text("shots")
                            .font(Theme.Font.caption2)
                            .foregroundStyle(Theme.Color.textTertiary)
                    }
                    HStack(spacing: Theme.Space.s4) {
                        Image(systemName: "flag.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(Theme.Color.success)
                        Text(String(format: "%.0f%%", combo.pickRatio * 100))
                            .font(Theme.Font.monoCaption)
                            .foregroundStyle(Theme.Color.textSecondary)
                        Text("•")
                            .font(Theme.Font.caption2)
                            .foregroundStyle(Theme.Color.textTertiary)
                        Text(apertureString)
                            .font(Theme.Font.monoCaption)
                            .foregroundStyle(Theme.Color.textSecondary)
                    }
                }
            }

            // Pick ratio progress bar
            GeometryReader { geo in
                let fullWidth = geo.size.width
                let targetWidth = fullWidth * CGFloat(combo.pickRatio)
                let animWidth = animating ? max(targetWidth, combo.pickRatio > 0 ? 3 : 0) : 0

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.Color.separator)
                        .frame(height: 3)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Theme.Color.success, Theme.Color.success.opacity(0.6)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: animWidth, height: 3)
                        .animation(
                            .spring(response: 0.55, dampingFraction: 0.78),
                            value: animating
                        )
                }
            }
            .frame(height: 3)
            .padding(.leading, 40)
        }
        .padding(.vertical, Theme.Space.s8)
        .padding(.horizontal, Theme.Space.s12)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.m)
                .fill(Theme.Color.overlaySoft)
        )
    }
}
