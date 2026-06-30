//
//  HorizontalMouseScrollWrapper.swift
//  DuckSort
//
//  On macOS, a SwiftUI horizontal ScrollView ignores a standard mouse
//  wheel because AppKit delivers vertical-axis scroll events and the
//  SwiftUI host only forwards them horizontally for trackpad two-finger
//  swipes. This wrapper installs a local NSEvent monitor that intercepts
//  scrollWheel events while the pointer is over the wrapped view and
//  re-posts them with the vertical delta mapped onto the horizontal axis.
//

import SwiftUI
import AppKit
import CoreGraphics

// MARK: - Public view wrapper

/// Drop-in wrapper that makes any horizontal ScrollView respond to a
/// regular mouse scroll wheel.
///
/// ```swift
/// HorizontalMouseScrollWrapper {
///     ScrollView(.horizontal, showsIndicators: false) { … }
/// }
/// ```
struct HorizontalMouseScrollWrapper<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .modifier(_HorizontalScrollWheelModifier())
    }
}

// MARK: - ViewModifier

private struct _HorizontalScrollWheelModifier: ViewModifier {
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear   { install(geo: geo) }
                        .onChange(of: geo.frame(in: .global)) { _, _ in
                            // frame changed (window move/resize); monitor
                            // re-reads the geometry on each event so no
                            // action needed here.
                        }
                }
            )
            .onDisappear {
                if let m = monitor {
                    NSEvent.removeMonitor(m)
                    monitor = nil
                }
            }
    }

    private func install(geo: GeometryProxy) {
        guard monitor == nil else { return }

        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [geo] event in
            // Only intercept when the mouse is inside our view's frame.
            guard let window = event.window else { return event }

            // geo.frame(in: .global) is in SwiftUI's flipped coordinate
            // system (origin top-left). Convert the NSEvent's window-space
            // location (origin bottom-left) to screen space, then check.
            let mouseInWindow = event.locationInWindow
            let mouseOnScreen = window.convertPoint(toScreen: mouseInWindow)
            let globalFrame = geo.frame(in: .global)

            // SwiftUI global frame: origin is top-left of the SwiftUI scene.
            // Convert to screen coordinates: flip Y using the screen height.
            guard let screen = window.screen ?? NSScreen.main else { return event }
            let screenH = screen.frame.height
            let screenFrame = CGRect(
                x: globalFrame.minX + window.frame.minX,
                y: screenH - globalFrame.maxY - window.frame.minY,
                width: globalFrame.width,
                height: globalFrame.height
            )

            guard screenFrame.contains(mouseOnScreen) else { return event }

            // Only redirect when vertical dominates (pure mouse wheel).
            let dy = event.scrollingDeltaY
            let dx = event.scrollingDeltaX
            guard abs(dy) > abs(dx), dy != 0 else { return event }

            // Build a CGEvent copy with axes swapped.
            guard let cg = event.cgEvent?.copy() else { return event }
            // Axis 1 = vertical, Axis 2 = horizontal in scroll wheel events.
            cg.setDoubleValueField(.scrollWheelEventDeltaAxis1,      value: 0)
            cg.setDoubleValueField(.scrollWheelEventDeltaAxis2,      value: Double(-dy))
            cg.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: 0)
            cg.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: Double(-dy))
            cg.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 0)
            cg.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: Double(-dy))

            return NSEvent(cgEvent: cg) ?? event
        }
    }
}
