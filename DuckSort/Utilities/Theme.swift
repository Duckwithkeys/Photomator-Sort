//
//  Theme.swift
//  DuckSort
//
//  Single source of truth for visual tokens. Replaces the ad-hoc
//  PhotomatorTheme + dsColor hex literals with one adaptive, light/dark,
//  audit-friendly design system.
//
//  Naming: project is DuckSort. All tokens live on `Theme`. Anything
//  outside this file should reference a token, not a raw color/spacing
//  literal.
//

import SwiftUI
import AppKit

enum Theme {

    // MARK: - Color (adaptive, light + dark)

    enum Color {

        static let background = SwiftUI.Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(red: 0.176, green: 0.176, blue: 0.176, alpha: 1.0)
                : NSColor(red: 0.96,  green: 0.96,  blue: 0.96,  alpha: 1.0)
        })

        static let sidebarBackground = SwiftUI.Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(red: 0.110, green: 0.110, blue: 0.110, alpha: 1.0)
                : NSColor(red: 0.92,  green: 0.92,  blue: 0.92,  alpha: 1.0)
        })

        static let toolbarBackground = SwiftUI.Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(red: 0.200, green: 0.200, blue: 0.200, alpha: 1.0)
                : NSColor(red: 0.94,  green: 0.94,  blue: 0.94,  alpha: 1.0)
        })

        static let cellBackground = SwiftUI.Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(red: 0.160, green: 0.160, blue: 0.160, alpha: 1.0)
                : NSColor(white: 1.0, alpha: 1.0)
        })

        static let footerBackground = SwiftUI.Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(red: 0.125, green: 0.125, blue: 0.125, alpha: 1.0)
                : NSColor(red: 0.88,  green: 0.88,  blue: 0.88,  alpha: 1.0)
        })

        static let separator = SwiftUI.Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(red: 0.227, green: 0.227, blue: 0.227, alpha: 1.0)
                : NSColor(red: 0.82,  green: 0.82,  blue: 0.82,  alpha: 1.0)
        })

        // Settings-window surfaces (darker than the main app, by design).
        static let surfaceBase        = SwiftUI.Color(red: 0.118, green: 0.118, blue: 0.118) // #1E1E1E
        static let surfaceSidebar     = SwiftUI.Color(red: 0.086, green: 0.086, blue: 0.086) // #161616
        static let surfaceSidebarList = SwiftUI.Color(red: 0.137, green: 0.137, blue: 0.137) // #232323
        static let surfaceRaised      = SwiftUI.Color(red: 0.173, green: 0.173, blue: 0.180) // #2C2C2E
        static let surfaceDivider     = SwiftUI.Color(red: 0.196, green: 0.196, blue: 0.196) // #323232
        static let surfaceStroke      = SwiftUI.Color(red: 0.235, green: 0.235, blue: 0.243) // #3C3C3E

        // Accent — defer to the system accent color so a user-chosen tint
        // is honored app-wide. Kept as a named token for places that need
        // to *read* the accent rather than re-type Color.accentColor.
        static let accent             = SwiftUI.Color.accentColor
        static let accentPressed      = SwiftUI.Color(nsColor: .controlAccentColor).opacity(0.85)

        // Semantic
        static let success            = SwiftUI.Color(red: 0.196, green: 0.776, blue: 0.408) // systemGreen
        static let warning            = SwiftUI.Color(red: 1.000, green: 0.733, blue: 0.247) // systemOrange
        static let danger             = SwiftUI.Color(red: 1.000, green: 0.271, blue: 0.227) // #FF453A
        static let rating             = SwiftUI.Color(red: 1.000, green: 0.804, blue: 0.196) // systemYellow

        // Text (adaptive)
        static let textPrimary = SwiftUI.Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(white: 1.0, alpha: 0.88)
                : NSColor(white: 0.0, alpha: 0.85)
        })
        static let textSecondary = SwiftUI.Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(white: 1.0, alpha: 0.50)
                : NSColor(white: 0.0, alpha: 0.65)
        })
        static let textTertiary = SwiftUI.Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(white: 1.0, alpha: 0.30)
                : NSColor(white: 0.0, alpha: 0.45)
        })
        static let textInverse  = SwiftUI.Color.white

        // Selection / row hover tints (over any background).
        static let rowSelectedFill   = SwiftUI.Color.accentColor.opacity(0.18)
        static let rowHoverFill      = SwiftUI.Color.primary.opacity(0.06)

        // Image-pane scrim (the photo viewer sits on a near-black scrim).
        static let scrim             = SwiftUI.Color.black

        // Overlays (capsules behind badges, captions).
        static let overlayDim        = SwiftUI.Color.black.opacity(0.60)
        static let overlayScrim      = SwiftUI.Color.black.opacity(0.30)
        static let overlaySoft       = SwiftUI.Color.white.opacity(0.06)
        static let overlaySofter     = SwiftUI.Color.white.opacity(0.04)

        // File-role chip colors. Shared between the grid cell's format pill
        // and the large viewer's "Files in Set" panel so both surfaces
        // agree on what colour means "RAW", "JPEG", "HEIF". The edit
        // wand uses `Theme.Color.warning` (yellow) for consistency with
        // the filmstrip's existing edit indicator. Hard-coded high-
        // contrast tones keep the chips readable on any system accent.
        enum FileColor {
            static let raw   = SwiftUI.Color(red: 0.85, green: 0.20, blue: 0.20) // red
            static let jpeg  = SwiftUI.Color(red: 0.18, green: 0.55, blue: 0.30) // green
            static let heif  = SwiftUI.Color(red: 0.20, green: 0.35, blue: 0.85) // indigo
            static let other = SwiftUI.Color.black.opacity(0.78)
        }
    }

    // MARK: - Spacing (4pt grid)

    enum Space {
        static let s2:  CGFloat = 2
        static let s4:  CGFloat = 4
        static let s6:  CGFloat = 6
        static let s8:  CGFloat = 8
        static let s10: CGFloat = 10
        static let s12: CGFloat = 12
        static let s14: CGFloat = 14
        static let s16: CGFloat = 16
        static let s20: CGFloat = 20
        static let s24: CGFloat = 24
        static let s28: CGFloat = 28
        static let s32: CGFloat = 32
        static let s44: CGFloat = 44 // macOS title bar height, roughly
        static let s56: CGFloat = 56
        static let s64: CGFloat = 64
        static let s72: CGFloat = 72 // traffic-light gap
    }

    // MARK: - Radius

    enum Radius {
        static let s:  CGFloat = 4
        static let m:  CGFloat = 6
        static let l:  CGFloat = 8
        static let xl: CGFloat = 12
    }

    // MARK: - Typography

    enum Font {
        static let display       = SwiftUI.Font.system(size: 34, weight: .bold)
        static let title         = SwiftUI.Font.system(size: 22, weight: .semibold)
        static let headline      = SwiftUI.Font.system(size: 17, weight: .semibold)
        static let body          = SwiftUI.Font.system(size: 13, weight: .regular)
        static let bodyBold      = SwiftUI.Font.system(size: 13, weight: .semibold)
        static let callout       = SwiftUI.Font.system(size: 13, weight: .medium)
        static let subheadline   = SwiftUI.Font.system(size: 12, weight: .regular)
        static let footnote      = SwiftUI.Font.system(size: 11, weight: .regular)
        static let caption       = SwiftUI.Font.system(size: 11, weight: .medium)
        static let caption2      = SwiftUI.Font.system(size: 10, weight: .medium)
        static let badge         = SwiftUI.Font.system(size: 10, weight: .bold)
        static let badgeTiny     = SwiftUI.Font.system(size: 9,  weight: .bold)
        static let iconBadge     = SwiftUI.Font.system(size: 12, weight: .bold)
        static let monoCaption   = SwiftUI.Font.system(size: 10, weight: .semibold, design: .monospaced)
        static let monoBody      = SwiftUI.Font.system(size: 11, weight: .regular, design: .monospaced)
        static let iconHero      = SwiftUI.Font.system(size: 36, weight: .regular)
        static let iconLarge     = SwiftUI.Font.system(size: 28, weight: .light)
    }

    // MARK: - Stroke

    enum Stroke {
        static let hairline: CGFloat = 1
        static let border:   CGFloat = 2
        static let heavy:    CGFloat = 2.5
    }
}

// MARK: - Back-compat shim removed.
//
// Historical callers used `PhotomatorTheme.selectedBlue`. All call sites now
// reference Theme tokens directly. If you re-introduce an old symbol, write
// the mapping here as a one-line alias and call it out in code review.
