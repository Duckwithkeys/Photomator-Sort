//
//  LiquidGlassStyle.swift
//  PhotomatorSort
//
//  Design system modifiers inspired by Photomator's dark professional aesthetic.
//  Provides flat dark panels, subtle hover highlights, and consistent styling.
//

import SwiftUI
import AppKit

// MARK: - Photomator Color Constants

enum PhotomatorTheme {
    static var background: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(red: 0.176, green: 0.176, blue: 0.176, alpha: 1.0)
            } else {
                return NSColor(red: 0.96, green: 0.96, blue: 0.96, alpha: 1.0)
            }
        })
    }
    
    static var sidebarBackground: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(red: 0.145, green: 0.145, blue: 0.145, alpha: 1.0)
            } else {
                return NSColor(red: 0.92, green: 0.92, blue: 0.92, alpha: 1.0)
            }
        })
    }
    
    static var toolbarBackground: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(red: 0.200, green: 0.200, blue: 0.200, alpha: 1.0)
            } else {
                return NSColor(red: 0.94, green: 0.94, blue: 0.94, alpha: 1.0)
            }
        })
    }
    
    static var cellBackground: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(red: 0.160, green: 0.160, blue: 0.160, alpha: 1.0)
            } else {
                return NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
            }
        })
    }
    
    static var footerBackground: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(red: 0.125, green: 0.125, blue: 0.125, alpha: 1.0)
            } else {
                return NSColor(red: 0.88, green: 0.88, blue: 0.88, alpha: 1.0)
            }
        })
    }
    
    static var separator: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(red: 0.227, green: 0.227, blue: 0.227, alpha: 1.0)
            } else {
                return NSColor(red: 0.82, green: 0.82, blue: 0.82, alpha: 1.0)
            }
        })
    }
    
    static let selectedBlue = Color(red: 0.251, green: 0.537, blue: 1.0)
    
    static var textPrimary: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(white: 1.0, alpha: 0.88)
            } else {
                return NSColor(white: 0.0, alpha: 0.85)
            }
        })
    }
    
    static var textSecondary: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(white: 1.0, alpha: 0.50)
            } else {
                return NSColor(white: 0.0, alpha: 0.65)
            }
        })
    }
    
    static var textTertiary: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(white: 1.0, alpha: 0.30)
            } else {
                return NSColor(white: 0.0, alpha: 0.45)
            }
        })
    }
}

extension View {
    /// Applies the Photomator-style sidebar background.
    func liquidGlassSidebar(cornerRadius: CGFloat = 0) -> some View {
        self
            .background(PhotomatorTheme.sidebarBackground)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    /// Applies a flat panel style with subtle border.
    func liquidGlassPanel(cornerRadius: CGFloat = 8, opacity: Double = 0.08) -> some View {
        self
            .background(PhotomatorTheme.cellBackground)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(PhotomatorTheme.separator, lineWidth: 1)
            )
    }

    /// Applies a flat button style with subtle hover and selection states.
    func liquidGlassButton(isHovered: Bool = false, isApplied: Bool = false, accentColor: Color = PhotomatorTheme.selectedBlue) -> some View {
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
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(
                        isApplied ? accentColor.opacity(0.5) : Color.primary.opacity(isHovered ? 0.15 : 0.08),
                        lineWidth: 1
                    )
            )
    }

    /// Applies the flat borderless button style from the sidebar.
    func flatSidebarButton(isHovered: Bool = false, isSelected: Bool = false, accentColor: Color = PhotomatorTheme.selectedBlue) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? accentColor.opacity(0.15) : (isHovered ? Color.primary.opacity(0.08) : Color.clear))
            )
            .contentShape(RoundedRectangle(cornerRadius: 6))
    }
}
