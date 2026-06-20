//
//  LiquidGlassStyle.swift
//  PhotomatorSort
//
//  Design system modifiers for the Apple iOS 27 style "Liquid Glass" theme.
//  Provides glassmorphism panels, cut-glass edge borders, and fluid button scales.
//

import SwiftUI

extension View {
    /// Applies a premium Liquid Glass panel style with blurred background and refractive border.
    func liquidGlassPanel(cornerRadius: CGFloat = 12, opacity: Double = 0.08) -> some View {
        self
            .background(.thinMaterial)
            .background(Color.white.opacity(opacity))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.18), .white.opacity(0.04), .black.opacity(0.10)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.15), radius: 10, y: 4)
    }

    /// Applies a refractive glass style suitable for buttons and interactive components.
    func liquidGlassButton(isHovered: Bool = false, isApplied: Bool = false, accentColor: Color = .accentColor) -> some View {
        self
            .background(
                ZStack {
                    if isApplied {
                        accentColor.opacity(0.15)
                    } else if isHovered {
                        Color.white.opacity(0.12)
                    } else {
                        Color.white.opacity(0.05)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        LinearGradient(
                            colors: [
                                isApplied ? accentColor.opacity(0.6) : .white.opacity(isHovered ? 0.25 : 0.12),
                                .white.opacity(0.02),
                                .black.opacity(0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}
