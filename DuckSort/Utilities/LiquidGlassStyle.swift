//
//  LiquidGlassStyle.swift
//  DuckSort
//
//  View modifiers for sidebar/panel/button styling. Visual tokens live in
//  Theme.swift; this file only defines layout-primitive helpers on top of
//  them.
//

import SwiftUI
import AppKit

extension View {
    /// Applies the DuckSort sidebar background.
    func liquidGlassSidebar(cornerRadius: CGFloat = 0) -> some View {
        self
            .background(Theme.Color.sidebarBackground)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    /// Applies a flat panel style with a subtle hairline border.
    func liquidGlassPanel(cornerRadius: CGFloat = Theme.Radius.l, opacity: Double = 0.08) -> some View {
        self
            .background(Theme.Color.cellBackground)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Theme.Color.separator, lineWidth: Theme.Stroke.hairline)
            )
    }

    /// Flat button with hover/selected states.
    func liquidGlassButton(
        isHovered: Bool = false,
        isApplied: Bool = false,
        accentColor: Color = Theme.Color.accent
    ) -> some View {
        self
            .background(
                ZStack {
                    if isApplied {
                        accentColor.opacity(0.20)
                    } else if isHovered {
                        Color.primary.opacity(0.08)
                    } else {
                        Color.primary.opacity(0.04)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.m))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.m)
                    .stroke(
                        isApplied ? accentColor.opacity(0.5)
                                  : Color.primary.opacity(isHovered ? 0.15 : 0.08),
                        lineWidth: Theme.Stroke.hairline
                    )
            )
    }

    /// Flat sidebar-row button (no inset shadow).
    func flatSidebarButton(
        isHovered: Bool = false,
        isSelected: Bool = false,
        accentColor: Color = Theme.Color.accent
    ) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.m)
                    .fill(
                        isSelected ? accentColor.opacity(0.15)
                                   : (isHovered ? Color.primary.opacity(0.08) : Color.clear)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.m))
    }
}
