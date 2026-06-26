//
//  ThumbnailView.swift
//  PhotomatorSort
//
//  Performance-critical path: thumbnails must load without ever blocking the
//  main thread or triggering the beach ball.
//
//  Architecture
//  ───────────
//  • ThumbnailView       — SwiftUI view (main actor). Observes ThumbnailLoader.
//  • ThumbnailLoader     — @MainActor ObservableObject. Only stores the result
//                          image; delegates ALL I/O to ThumbnailService.
//  • ThumbnailService    — Global actor (not MainActor). Owns an async semaphore
//                          that caps concurrent decodes to 4. All CGImageSource,
//                          QL, and NSWorkspace calls happen here, never on main.
//  • ThumbnailCache      — Thread-safe NSCache wrapper. Reads & writes happen
//                          on ThumbnailService's executor, never on main.
//

import AppKit
import ImageIO
import QuickLookThumbnailing
import SwiftUI

// MARK: - View

struct ThumbnailView: View {
    let url: URL?
    var size: CGSize = CGSize(width: 300, height: 300)
    var cornerRadius: CGFloat = Theme.Radius.xl
    @StateObject private var loader = ThumbnailLoader()

    var body: some View {
        // Color.clear anchors the layout size from the parent (aspectRatio +
        // maxWidth). A bare GeometryReader as root collapses to zero inside ZStack.
        Color.clear
            .overlay {
                GeometryReader { geo in
                    ZStack {
                        // Placeholder — always visible; replaced by photo when ready
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Theme.Color.cellBackground,
                                        Theme.Color.separator.opacity(0.6)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )

                        if let image = loader.image {
                            Image(nsImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: geo.size.width, height: geo.size.height)
                                .clipped()
                                .transition(.opacity.animation(.easeIn(duration: 0.15)))
                        } else {
                            Image(systemName: "photo")
                                .font(Theme.Font.iconHero)
                                .foregroundStyle(Theme.Color.textTertiary)
                                .frame(width: geo.size.width, height: geo.size.height)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                }
            }
        .task(id: url) {
            guard let url else { return }
            // Fast cache hit — no I/O at all
            if let hit = ThumbnailCache.global.image(for: url) {
                loader.image = hit
                return
            }

            loader.image = nil

            // Short debounce so we skip cells the user scrolled past quickly.
            // 50ms is enough to feel instant for deliberate pauses.
            do { try await Task.sleep(nanoseconds: 50_000_000) } catch { return }

            // Wait for scroll momentum to settle before kicking off I/O
            if ScrollStateObserver.shared.isScrolling {
                // Poll at 80ms intervals; each sleep is cancellable
                while ScrollStateObserver.shared.isScrolling {
                    do { try await Task.sleep(nanoseconds: 80_000_000) } catch { return }
                }
            }

            guard !Task.isCancelled else { return }

            // Delegate the actual decode to the off-main ThumbnailService
            if let result = await ThumbnailService.shared.thumbnail(for: url, size: size) {
                guard !Task.isCancelled else { return }
                loader.image = result   // @MainActor publish
            }
        }
    }
}

// MARK: - Loader (MainActor — only holds the published image)

@MainActor
final class ThumbnailLoader: ObservableObject {
    @Published var image: NSImage?
}

// MARK: - Service (runs on ThumbnailActor, never on main thread)

@globalActor
actor ThumbnailActor {
    static let shared = ThumbnailActor()
}

@ThumbnailActor
final class ThumbnailService {
    static let shared = ThumbnailService()

    private let cache = ThumbnailCache()
    /// Cap concurrent decodes to avoid flooding the I/O subsystem.
    private let semaphore = AsyncSemaphore(limit: 4)

    private init() {}

    // MARK: - Decode pipeline

    func thumbnail(for url: URL?, size: CGSize) async -> NSImage? {
        guard let url else { return nil }

        // Check cache again on this actor (avoids a redundant decode if two
        // cells request the same URL at nearly the same time).
        if let hit = ThumbnailCache.global.image(for: url) { return hit }

        // Acquire a slot in the semaphore — suspends (non-blocking) when full.
        // A single try/catch around the whole decode ensures `release()` always runs
        // exactly once regardless of cancellation or errors, without using `defer`.
        do {
            let result = try await decode(url: url, size: size)
            await semaphore.release()
            return result
        } catch {
            await semaphore.release()
            return nil
        }
    }

    private func decode(url: URL, size: CGSize) async throws -> NSImage? {
        try Task.checkCancellation()
        await semaphore.acquire()

        // ── 1. Fast path: ImageIO embedded thumbnail ─────────────────────────
        let maxPixels = max(size.width, size.height)
        let ext = url.pathExtension.lowercased()
        // RAW files never have an embedded JPEG-quality thumbnail at full size;
        // always regenerate from the raw data for those extensions.
        let alwaysCreate = FileExtension.rawLikeExtensions.contains(ext)

        if let cgImage = decodeWithImageIO(url: url, maxPixels: maxPixels, alwaysCreate: alwaysCreate) {
            try Task.checkCancellation()
            let ns = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            ThumbnailCache.global.insert(ns, for: url)
            return ns
        }

        // ── 1b. HEIF / HEIC native fallback ─────────────────────────────────
        // Some HEIF files refuse to produce a thumbnail via
        // `CGImageSourceCreateThumbnailAtIndex` (especially multi-image HEIC
        // bursts or files with unusual orientation metadata). Falling back
        // to `NSImage(contentsOf:)` uses the system codec and succeeds where
        // the embedded-thumbnail path does not.
        if FileExtension.heifLikeExtensions.contains(ext) {
            if let ns = loadWithNSImage(url: url, maxPixels: maxPixels) {
                try Task.checkCancellation()
                ThumbnailCache.global.insert(ns, for: url)
                return ns
            }
        }

        // ── 2. Slow path: QuickLook ──────────────────────────────────────────
        // QLThumbnailGenerator is async and doesn't block the calling thread.
        let scale = await MainActor.run { NSScreen.main?.backingScaleFactor ?? 2 }
        try Task.checkCancellation()
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: scale,
            representationTypes: .thumbnail
        )
        do {
            let rep = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
            try Task.checkCancellation()
            ThumbnailCache.global.insert(rep.nsImage, for: url)
            return rep.nsImage
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // ── 3. Last resort: generic file icon ────────────────────────────
            // NSWorkspace.icon is synchronous disk I/O — keep it off main.
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            ThumbnailCache.global.insert(icon, for: url)
            return icon
        }
    }

    // Synchronous CGImageSource decode — runs fully on ThumbnailActor (not main)
    private func decodeWithImageIO(url: URL, maxPixels: CGFloat, alwaysCreate: Bool) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        guard !Task.isCancelled else { return nil }
        let options: [CFString: Any] = [
            (alwaysCreate
                ? kCGImageSourceCreateThumbnailFromImageAlways
                : kCGImageSourceCreateThumbnailFromImageIfAbsent): true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// HEIF-friendly fallback. Uses `NSImage(contentsOf:)` (which goes
    /// through the system codec and handles HEIC/HEIF reliably) and then
    /// downsamples to the requested pixel budget.
    private func loadWithNSImage(url: URL, maxPixels: CGFloat) -> NSImage? {
        guard let image = NSImage(contentsOf: url) else { return nil }
        guard let rep = image.representations.first else { return nil }
        let fullW = CGFloat(rep.pixelsWide > 0 ? rep.pixelsWide : Int(image.size.width))
        let fullH = CGFloat(rep.pixelsHigh > 0 ? rep.pixelsHigh : Int(image.size.height))
        guard fullW > 0, fullH > 0 else { return image }
        let scale = min(maxPixels / max(fullW, fullH), 1.0)
        guard scale < 1.0 else { return image }
        let targetW = Int(fullW * scale)
        let targetH = Int(fullH * scale)
        let resized = NSImage(size: NSSize(width: targetW, height: targetH))
        resized.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(x: 0, y: 0, width: targetW, height: targetH),
            from: NSRect(x: 0, y: 0, width: image.size.width, height: image.size.height),
            operation: .copy,
            fraction: 1.0
        )
        resized.unlockFocus()
        return resized
    }
}

// MARK: - Thread-safe cache (NSCache is already thread-safe internally)

final class ThumbnailCache {
    /// Single process-wide cache shared by ThumbnailService and direct callers.
    static let global = ThumbnailCache()

    private let cache = NSCache<NSURL, NSImage>()

    init() {
        // Scale the cache to the host's physical memory. A professional
        // photo workflow on a 5,000+ photo library evicts ~88% of
        // thumbnails on a 600/80MB cache, causing visible re-decodes
        // while scrolling. Modern machines have plenty of RAM; let them
        // keep more thumbnails hot.
        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        let memoryGB = Int(physicalMemory / (1024 * 1024 * 1024))
        if memoryGB >= 32 {
            cache.countLimit = 2500
            cache.totalCostLimit = 400 * 1024 * 1024
        } else if memoryGB >= 16 {
            cache.countLimit = 1500
            cache.totalCostLimit = 200 * 1024 * 1024
        } else {
            cache.countLimit = 800
            cache.totalCostLimit = 120 * 1024 * 1024
        }
    }

    func image(for url: URL) -> NSImage? {
        cache.object(forKey: url.standardizedFileURL as NSURL)
    }

    func insert(_ image: NSImage, for url: URL) {
        let cost = Int(max(image.size.width * image.size.height * 4, 1))
        cache.setObject(image, forKey: url.standardizedFileURL as NSURL, cost: cost)
    }
}

// MARK: - Async semaphore (simple non-blocking concurrency gate)

actor AsyncSemaphore {
    private let limit: Int
    private var current = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) { self.limit = limit }

    func acquire() async {
        if current < limit {
            current += 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() async {
        if let next = waiters.first {
            waiters.removeFirst()
            next.resume()
        } else {
            current -= 1
        }
    }
}
