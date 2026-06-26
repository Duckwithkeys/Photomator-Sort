//
//  FloatingWindowManager.swift
//  PhotomatorSort
//
//  Central manager for lightweight, floating utility windows.
//

import SwiftUI
import AppKit

final class FloatingPanel<Content: View>: NSPanel {
    init(title: String, content: Content, width: CGFloat, height: CGFloat, isResizable: Bool = true, hideTrafficLights: Bool = false) {
        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        if isResizable {
            style.insert(.resizable)
        }

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: style,
            backing: .buffered,
            defer: false
        )

        self.title = title
        self.level = .floating
        self.isFloatingPanel = false
        self.hidesOnDeactivate = false
        self.titlebarAppearsTransparent = false
        self.titleVisibility = .visible

        let hostingView = NSHostingView(rootView: content)
        self.contentView = hostingView

        self.center()

        if hideTrafficLights {
            self.standardWindowButton(.closeButton)?.isHidden = true
            self.standardWindowButton(.miniaturizeButton)?.isHidden = true
            self.standardWindowButton(.zoomButton)?.isHidden = true
        }
    }

    override var canBecomeKey: Bool {
        return true
    }
}

@MainActor
final class FloatingWindowManager: ObservableObject {
    static let shared = FloatingWindowManager()

    weak var activeViewModel: PhotoLibraryViewModel? {
        didSet { isReady = (activeViewModel != nil) }
    }

    /// Drives `.disabled` state for menu commands that require an active library.
    @Published private(set) var isReady = false

    private var settingsController: NSWindowController?
    private var xmpInspectorController: NSWindowController?

    private init() {}

    func showSettings(viewModel: PhotoLibraryViewModel, initialTab: SettingsTab = .rules) {
        if let controller = settingsController {
            if let win = controller.window,
               let hosting = win.contentView as? NSHostingView<AnyView> {
                hosting.rootView = AnyView(
                    SettingsPaneView(
                        viewModel: viewModel,
                        initialTab: initialTab,
                        onClose: { [weak controller] in controller?.close() }
                    )
                )
            }
            controller.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = SettingsPaneView(
            viewModel: viewModel,
            initialTab: initialTab,
            onClose: { [weak self] in self?.settingsController?.close() }
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = ""
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 820, height: 560)
        window.backgroundColor = NSColor(red: 0x1E/255, green: 0x1E/255, blue: 0x1E/255, alpha: 1)
        window.center()

        let hosting = NSHostingView(rootView: AnyView(view))
        hosting.frame = NSRect(x: 0, y: 0, width: 960, height: 720 + 28)
        hosting.autoresizingMask = [.width, .height]
        window.contentView = hosting

        let delegate = PanelDelegate { [weak self] in
            self?.settingsController = nil
        }
        window.delegate = delegate
        window.setAssociatedDelegate(delegate)

        let controller = NSWindowController(window: window)
        self.settingsController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeAll() {
        settingsController?.close()
        xmpInspectorController?.close()
    }

    /// Show a small floating "XMP tag inspector" overlay listing tags found
    /// in XMP sidecars that aren't defined in the active pack. Re-uses the
    /// same controller if it's already open.
    func showXMPTagInspector(viewModel: PhotoLibraryViewModel) {
        if let controller = xmpInspectorController {
            if let win = controller.window,
               let hosting = win.contentView as? NSHostingView<AnyView> {
                hosting.rootView = AnyView(
                    XMPTagInspectorView(
                        viewModel: viewModel,
                        onClose: { [weak controller] in controller?.close() }
                    )
                )
            }
            controller.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = XMPTagInspectorView(
            viewModel: viewModel,
            onClose: { [weak self] in self?.xmpInspectorController?.close() }
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "XMP Tags Not in Active Pack"
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 360, height: 320)
        window.backgroundColor = NSColor(red: 0x1E/255, green: 0x1E/255, blue: 0x1E/255, alpha: 1)
        window.level = .floating
        window.center()

        let hosting = NSHostingView(rootView: AnyView(view))
        hosting.frame = NSRect(x: 0, y: 0, width: 460, height: 520 + 28)
        hosting.autoresizingMask = [.width, .height]
        window.contentView = hosting

        let delegate = PanelDelegate { [weak self] in
            self?.xmpInspectorController = nil
        }
        window.delegate = delegate
        window.setAssociatedDelegate(delegate)

        let controller = NSWindowController(window: window)
        self.xmpInspectorController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Delegate to retain delegate instance
private var delegateKey: UInt8 = 0

extension NSWindow {
    func setAssociatedDelegate(_ delegate: NSWindowDelegate) {
        objc_setAssociatedObject(self, &delegateKey, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}

private final class PanelDelegate: NSObject, NSWindowDelegate {
    private let onClose: () -> Void
    
    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }
    
    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}
