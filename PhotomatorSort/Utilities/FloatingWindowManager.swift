//
//  FloatingWindowManager.swift
//  PhotomatorSort
//
//  Central manager for lightweight, floating utility windows.
//

import SwiftUI
import AppKit

final class FloatingPanel<Content: View>: NSPanel {
    init(title: String, content: Content, width: CGFloat, height: CGFloat, isResizable: Bool = true) {
        var style: NSWindow.StyleMask = [.titled, .utilityWindow]
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
        self.isFloatingPanel = true
        self.hidesOnDeactivate = false
        self.titlebarAppearsTransparent = false
        
        // Host the SwiftUI view
        let hostingView = NSHostingView(rootView: content)
        self.contentView = hostingView
        
        self.center()

        // Remove the traffic light buttons entirely
        self.standardWindowButton(.closeButton)?.isHidden = true
        self.standardWindowButton(.miniaturizeButton)?.isHidden = true
        self.standardWindowButton(.zoomButton)?.isHidden = true
    }
    
    override var canBecomeKey: Bool {
        return true
    }
}

@MainActor
final class FloatingWindowManager {
    static let shared = FloatingWindowManager()
    
    weak var activeViewModel: PhotoLibraryViewModel?
    
    private var tagManagerPanel: NSPanel?
    private var ruleEditorPanel: NSPanel?
    private var shortcutsPanel: NSPanel?
    
    private init() {}
    
    func showTagManager(viewModel: PhotoLibraryViewModel) {
        if let panel = tagManagerPanel {
            panel.makeKeyAndOrderFront(nil)
            return
        }
        
        let view = TagManagerView(viewModel: viewModel, tagStore: viewModel.tagStore)
        let panel = FloatingPanel(
            title: "Tag Manager",
            content: view,
            width: 680,
            height: 580
        )
        
        panel.minSize = NSSize(width: 640, height: 520)
        
        let delegate = PanelDelegate { [weak self] in
            self?.tagManagerPanel = nil
        }
        panel.delegate = delegate
        panel.setAssociatedDelegate(delegate)
        
        self.tagManagerPanel = panel
        panel.makeKeyAndOrderFront(nil)
    }
    
    func showRuleEditor(viewModel: PhotoLibraryViewModel) {
        if let panel = ruleEditorPanel {
            panel.makeKeyAndOrderFront(nil)
            return
        }
        
        let view = ExportRuleEditorView(viewModel: viewModel, ruleStore: viewModel.ruleStore, tagStore: viewModel.tagStore)
        let panel = FloatingPanel(
            title: "Export Routing Rules",
            content: view,
            width: 860,
            height: 600
        )
        
        panel.minSize = NSSize(width: 820, height: 540)
        
        let delegate = PanelDelegate { [weak self] in
            self?.ruleEditorPanel = nil
        }
        panel.delegate = delegate
        panel.setAssociatedDelegate(delegate)
        
        self.ruleEditorPanel = panel
        panel.makeKeyAndOrderFront(nil)
    }
    
    func showShortcutsViewer(viewModel: PhotoLibraryViewModel) {
        if let panel = shortcutsPanel {
            panel.makeKeyAndOrderFront(nil)
            return
        }
        
        // Wrap the ShortcutsPopoverView in a ScrollView to fit nicely
        let view = ScrollView {
            ShortcutsPopoverView(viewModel: viewModel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        
        let panel = FloatingPanel(
            title: "Keyboard Shortcuts",
            content: view,
            width: 340,
            height: 480,
            isResizable: true
        )
        
        panel.minSize = NSSize(width: 320, height: 360)
        
        let delegate = PanelDelegate { [weak self] in
            self?.shortcutsPanel = nil
        }
        panel.delegate = delegate
        panel.setAssociatedDelegate(delegate)
        
        self.shortcutsPanel = panel
        panel.makeKeyAndOrderFront(nil)
    }
    
    func closeAll() {
        tagManagerPanel?.close()
        ruleEditorPanel?.close()
        shortcutsPanel?.close()
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
