//
//  ScrollStateObserver.swift
//  PhotomatorSort
//

import AppKit
import Foundation
import SwiftUI

@MainActor
final class ScrollStateObserver: ObservableObject {
    static let shared = ScrollStateObserver()
    
    @Published private(set) var isScrolling = false
    private var timer: Timer?

    private init() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleScrollStart), name: NSScrollView.willStartLiveScrollNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleScrollEnd), name: NSScrollView.didEndLiveScrollNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleScrollMove), name: NSScrollView.didLiveScrollNotification, object: nil)
    }

    @objc private func handleScrollStart() {
        isScrolling = true
        timer?.invalidate()
    }

    @objc private func handleScrollEnd() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.075, repeats: false) { _ in
            Task { @MainActor in
                self.isScrolling = false
            }
        }
    }

    @objc private func handleScrollMove() {
        isScrolling = true
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.075, repeats: false) { _ in
            Task { @MainActor in
                self.isScrolling = false
            }
        }
    }
}
