//
//  ThumbnailView.swift
//  PhotomatorSort
//

import AppKit
import QuickLookThumbnailing
import SwiftUI
import ImageIO

struct ThumbnailView: View {
    let url: URL?
    var size: CGSize = CGSize(width: 300, height: 300)
    @StateObject private var loader = ThumbnailLoader()

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(nsColor: .controlBackgroundColor),
                            Color(nsColor: .quaternaryLabelColor).opacity(0.22)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            if let image = (loader.loadedURL == url ? loader.image : nil) ?? ThumbnailLoader.cachedImage(for: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(4)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 34))
                    .foregroundStyle(.secondary)
            }
        }
        .clipped()
        .task(id: url) {
            do {
                // 80ms debounce: Skip loading thumbnails if the user scrolls past quickly
                try await Task.sleep(nanoseconds: 80_000_000)
                await loader.load(url: url, size: size)
            } catch {
                // Task cancelled, ignore
            }
        }
    }
}

@MainActor
final class ThumbnailLoader: ObservableObject {
    @Published var image: NSImage?
    @Published var loadedURL: URL? = nil
    static let cache = ThumbnailCache()

    static func cachedImage(for url: URL?) -> NSImage? {
        guard let url else { return nil }
        return cache.image(for: url)
    }

    func load(url: URL?, size: CGSize) async {
        let cached = Self.cachedImage(for: url)
        if cached != nil {
            image = cached
            loadedURL = url
            return
        }

        image = nil
        loadedURL = nil
        guard let url else { return }

        // 1. Try to load using the fast ImageIO CGImageSource in a detached task
        let maxPixelSize = max(size.width, size.height)
        let isHEIF = url.pathExtension.lowercased() == "hif" || url.pathExtension.lowercased() == "heic"
        let decodeTask = Task.detached(priority: .userInitiated) { () -> CGImage? in
            if Task.isCancelled { return nil }
            guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            if Task.isCancelled { return nil }
            let options: [CFString: Any] = [
                isHEIF ? kCGImageSourceCreateThumbnailFromImageAlways : kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                kCGImageSourceCreateThumbnailWithTransform: true
            ]
            guard let thumbnailCG = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else { return nil }
            return thumbnailCG
        }

        let cgImage = await withTaskCancellationHandler {
            await decodeTask.value
        } onCancel: {
            decodeTask.cancel()
        }

        if let cgImage {
            if Task.isCancelled { return }
            let thumbnail = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            Self.cache.insert(thumbnail, for: url)
            image = thumbnail
            loadedURL = url
            return
        }

        // 2. Try QLThumbnailGenerator as backup
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: .thumbnail
        )

        do {
            let representation = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
            if Task.isCancelled { return }
            Self.cache.insert(representation.nsImage, for: url)
            image = representation.nsImage
            loadedURL = url
        } catch is CancellationError {
            return
        } catch {
            if Task.isCancelled { return }
            let fallback = NSWorkspace.shared.icon(forFile: url.path)
            if Task.isCancelled { return }
            Self.cache.insert(fallback, for: url)
            image = fallback
            loadedURL = url
        }
    }
}

final class ThumbnailCache {
    private let cache = NSCache<NSURL, NSImage>()

    init() {
        cache.countLimit = 600
        cache.totalCostLimit = 80 * 1024 * 1024
    }

    func image(for url: URL) -> NSImage? {
        cache.object(forKey: url.standardizedFileURL as NSURL)
    }

    func insert(_ image: NSImage, for url: URL) {
        let pixels = max(image.size.width * image.size.height, 1)
        cache.setObject(image, forKey: url.standardizedFileURL as NSURL, cost: Int(pixels * 4))
    }
}
