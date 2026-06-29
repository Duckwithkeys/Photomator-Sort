//
//  AutoTagSuggestionsView.swift
//  DuckSort
//
//  Renders auto-tag suggestions in the large image viewer sidebar.
//  Overhauled with high-fidelity glassmorphism aesthetic, interactive pills,
//  confidence-colored pulsing dots, hover glows, and a spacious two-row layout
//  to prevent text wrapping and truncation in tight sidebar dimensions.
//

import SwiftUI

struct AutoTagSuggestionsView: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel

    private var suggestions: [AutoTagSuggestion] {
        guard let photoSet = viewModel.currentFocusedPhotoSet else { return [] }
        return viewModel.suggestedTags(for: photoSet)
    }

    var body: some View {
        Group {
            if !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Space.s12) {
                    VStack(alignment: .leading, spacing: Theme.Space.s8) {
                        HStack(spacing: Theme.Space.s6) {
                            Image(systemName: "brain.head.profile")
                                .foregroundStyle(Theme.Color.accent)
                                .font(.system(size: 11, weight: .semibold))

                            Text("AI VISION MACHINE LEARNING")
                                .font(Theme.Font.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(Theme.Color.textTertiary)

                            Spacer()

                            Text("\(suggestions.count)")
                                .font(Theme.Font.badgeTiny)
                                .foregroundStyle(Theme.Color.textInverse)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1.5)
                                .background(Theme.Color.accent, in: Capsule())
                        }

                        ForEach(suggestions) { suggestion in
                            AutoTagSuggestionCard(viewModel: viewModel, suggestion: suggestion)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Auto-Tag Suggestion Card Helper

struct AutoTagSuggestionCard: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel
    let suggestion: AutoTagSuggestion
    @State private var isHovered = false

    private var isExistingTag: Bool {
        suggestion.categoryID != nil
    }

    private var confidenceColor: Color {
        switch suggestion.confidence {
        case .high:   return Theme.Color.success
        case .medium: return Theme.Color.warning
        case .low:    return Theme.Color.textTertiary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s8) {
            // First Row: Tag Pill + Actions
            HStack(spacing: Theme.Space.s4) {
                // Tag Pill (Clickable badge to accept the suggestion)
                Button {
                    viewModel.acceptSuggestion(suggestion)
                } label: {
                    Text(suggestion.tagName)
                        .font(Theme.Font.caption)
                        .fontWeight(.bold)
                        .padding(.horizontal, Theme.Space.s8)
                        .padding(.vertical, 2.5)
                        .background(
                            Capsule().fill(isExistingTag ? Theme.Color.accent.opacity(0.08) : Theme.Color.warning.opacity(0.08))
                        )
                        .foregroundStyle(isExistingTag ? Theme.Color.accent : Theme.Color.warning)
                        .overlay(
                            Capsule().stroke(
                                isExistingTag ? Theme.Color.accent.opacity(0.25) : Theme.Color.warning.opacity(0.25),
                                style: StrokeStyle(lineWidth: 1, dash: isExistingTag ? [] : [2, 2])
                            )
                        )
                }
                .buttonStyle(.plain)
                .help("Click tag to accept suggestion")

                Spacer(minLength: 4)

                // Accept & Dismiss Actions
                HStack(spacing: Theme.Space.s6) {
                    Button {
                        viewModel.acceptSuggestion(suggestion)
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Theme.Color.textInverse)
                            .frame(width: 18, height: 18)
                            .background(Theme.Color.success, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Accept Suggestion")

                    Button {
                        viewModel.dismissSuggestion(suggestion)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(Theme.Color.textSecondary)
                            .frame(width: 18, height: 18)
                            .background(isHovered ? Color.red.opacity(0.2) : Theme.Color.overlaySoft, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Dismiss Suggestion")
                }
            }

            // Second Row: Reason & Confidence Metadata
            HStack(spacing: 4) {
                // Confidence pulsing dot
                Circle()
                    .fill(confidenceColor)
                    .frame(width: 5, height: 5)
                    .shadow(color: confidenceColor.opacity(0.4), radius: 1.5)

                Text(suggestion.confidence.rawValue.uppercased())
                    .font(Theme.Font.badgeTiny)
                    .foregroundStyle(confidenceColor)

                Text("•")
                    .font(Theme.Font.badgeTiny)
                    .foregroundStyle(Theme.Color.textTertiary)

                Text(suggestion.reason)
                    .font(Theme.Font.badgeTiny)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.leading, 1)
        }
        .padding(.horizontal, Theme.Space.s12)
        .padding(.vertical, Theme.Space.s10)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.l)
                .fill(Theme.Color.cellBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.l)
                .stroke(isHovered ? confidenceColor.opacity(0.35) : Theme.Color.separator, lineWidth: Theme.Stroke.hairline)
                .shadow(color: isHovered ? confidenceColor.opacity(0.12) : Color.clear, radius: 4)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}
