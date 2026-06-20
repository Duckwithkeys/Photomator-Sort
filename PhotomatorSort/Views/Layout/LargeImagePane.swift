//
//  LargeImagePane.swift
//  PhotomatorSort
//
//  Full-canvas image viewer for the culling flow. Displays the focused
//  photo at high resolution with pan/zoom support. Uses QuickLook
//  thumbnailing for fast initial load.
//

import AppKit
import QuickLookThumbnailing
import SwiftUI
import ImageIO

struct LargeImagePane: View {
    let photoSet: PhotoSet
    @StateObject private var imageLoader = LargeImageLoader()
    @State private var zoomScale: CGFloat = 1.0
    @State private var currentAmount: CGFloat = 0.0 // Tracks active pinch change
    @State private var panOffset: CGSize = .zero

    private let minZoom: CGFloat = 0.5
    private let maxZoom: CGFloat = 5.0

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            let highResImage = (imageLoader.loadedURL == photoSet.preferredPreviewURL ? imageLoader.image : nil) ?? LargeImageLoader.cachedImage(for: photoSet.preferredPreviewURL)
            let lowResImage = ThumbnailLoader.cachedImage(for: photoSet.preferredPreviewURL)

            if highResImage != nil || lowResImage != nil {
                GeometryReader { geometry in
                    ZStack {
                        Color.clear
                        
                        if let lowRes = lowResImage, highResImage == nil {
                            Image(nsImage: lowRes)
                                .resizable()
                                .interpolation(.low)
                                .scaledToFit()
                                .scaleEffect(zoomScale + currentAmount)
                                .offset(panOffset)
                                .blur(radius: 12)
                                .opacity(0.8)
                        }
                        
                        if let highRes = highResImage {
                            Image(nsImage: highRes)
                                .resizable()
                                .interpolation(.high)
                                .scaledToFit()
                                .scaleEffect(zoomScale + currentAmount)
                                .offset(panOffset)
                                .transition(.opacity)
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                currentAmount = value - 1.0
                            }
                            .onEnded { value in
                                zoomScale = clamp(zoomScale + currentAmount)
                                currentAmount = 0
                            }
                            .simultaneously(
                                with: DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        if (zoomScale + currentAmount) > 1.0 {
                                            panOffset = value.translation
                                        }
                                    }
                            )
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.spring()) {
                            if zoomScale > 1.0 {
                                zoomScale = 1.0
                                panOffset = .zero
                            } else if let nsImage = highResImage ?? lowResImage {
                                let fitScale = min(
                                    geometry.size.width / nsImage.size.width,
                                    geometry.size.height / nsImage.size.height
                                )
                                zoomScale = max(fitScale * 2.0, 1.5)
                                panOffset = .zero
                            }
                        }
                    }
                    .contextMenu {
                        Button("Reveal in Finder") {
                            if let url = photoSet.preferredPreviewURL {
                                NSWorkspace.shared.activateFileViewerSelecting([url])
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottomTrailing) {
                    HStack(spacing: 10) {
                        Button {
                            withAnimation(.spring()) {
                                zoomScale = clamp(zoomScale * 0.7)
                                panOffset = .zero
                            }
                        } label: {
                            Image(systemName: "minus.magnifyingglass")
                                .font(.title3)
                                .foregroundStyle(.white.opacity(0.7))
                                .padding(8)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)

                        Text(String(format: "%.0f%%", (zoomScale + currentAmount) * 100))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.horizontal, 8)
                            .background(.ultraThinMaterial, in: Capsule())

                        Button {
                            withAnimation(.spring()) {
                                zoomScale = clamp(zoomScale * 1.4)
                                panOffset = .zero
                            }
                        } label: {
                            Image(systemName: "plus.magnifyingglass")
                                .font(.title3)
                                .foregroundStyle(.white.opacity(0.7))
                                .padding(8)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)

                        Button {
                            withAnimation(.spring()) {
                                zoomScale = 1.0
                                panOffset = .zero
                            }
                        } label: {
                            Image(systemName: "arrow.2.squarepath")
                                .font(.title3)
                                .foregroundStyle(.white.opacity(0.7))
                                .padding(8)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Reset zoom")
                    }
                    .padding(12)
                }
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .task(id: photoSet.id) {
            zoomScale = 1.0
            currentAmount = 0
            panOffset = .zero
            await imageLoader.load(url: photoSet.preferredPreviewURL)
        }
    }

    @MainActor
    func clamp(_ value: CGFloat) -> CGFloat {
        max(minZoom, min(maxZoom, value))
    }
}

// MARK: - High-res image loader

@MainActor
final class LargeImageLoader: ObservableObject {
    @Published var image: NSImage?
    @Published var loadedURL: URL? = nil

    fileprivate static let cache: NSCache<NSURL, NSImage> = {
        let c = NSCache<NSURL, NSImage>()
        c.countLimit = 50
        c.totalCostLimit = 200 * 1024 * 1024 // 200MB limit
        return c
    }()

    private static func cost(for image: NSImage) -> Int {
        if let rep = image.representations.first {
            let w = rep.pixelsWide
            let h = rep.pixelsHigh
            if w > 0 && h > 0 {
                return w * h * 4
            }
        }
        return Int(image.size.width * image.size.height * 4)
    }

    static func cachedImage(for url: URL?) -> NSImage? {
        guard let url else { return nil }
        return cache.object(forKey: url.standardizedFileURL as NSURL)
    }

    static func preload(url: URL?) {
        guard let url else { return }
        let standardized = url.standardizedFileURL
        if cache.object(forKey: standardized as NSURL) != nil {
            return
        }
        
        let isHEIF = url.pathExtension.lowercased() == "hif" || url.pathExtension.lowercased() == "heic"
        Task.detached(priority: .userInitiated) {
            guard let imageSource = CGImageSourceCreateWithURL(standardized as CFURL, nil) else { return }
            let options: [CFString: Any] = [
                isHEIF ? kCGImageSourceCreateThumbnailFromImageAlways : kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
                kCGImageSourceThumbnailMaxPixelSize: CGFloat(2048),
                kCGImageSourceCreateThumbnailWithTransform: true
            ]
            guard let thumbnailCG = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else { return }
            
            let previewImage = NSImage(cgImage: thumbnailCG, size: NSSize(width: thumbnailCG.width, height: thumbnailCG.height))
            let cost = thumbnailCG.width * thumbnailCG.height * 4
            
            await MainActor.run {
                cache.setObject(previewImage, forKey: standardized as NSURL, cost: cost)
            }
        }
    }

    func load(url: URL?) async {
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
        // We load as CGImage (which is thread-safe and has no Sendable restrictions)
        let isHEIF = url.pathExtension.lowercased() == "hif" || url.pathExtension.lowercased() == "heic"
        let decodeTask = Task.detached(priority: .userInitiated) { () -> CGImage? in
            if Task.isCancelled { return nil }
            guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            if Task.isCancelled { return nil }
            let options: [CFString: Any] = [
                isHEIF ? kCGImageSourceCreateThumbnailFromImageAlways : kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
                kCGImageSourceThumbnailMaxPixelSize: CGFloat(2048),
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
            // Instantiate NSImage on the Main Actor
            let previewImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            let cost = cgImage.width * cgImage.height * 4
            Self.cache.setObject(previewImage, forKey: url.standardizedFileURL as NSURL, cost: cost)
            image = previewImage
            loadedURL = url
            return
        }

        // 2. Try QuickLook as a backup
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: 2048, height: 2048),
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: .thumbnail
        )

        do {
            let representation = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
            if Task.isCancelled { return }
            let nsImage = representation.nsImage
            let cost = representation.cgImage.width * representation.cgImage.height * 4
            Self.cache.setObject(nsImage, forKey: url.standardizedFileURL as NSURL, cost: cost)
            image = nsImage
            loadedURL = url
        } catch is CancellationError {
            // Task was cancelled, do not write fallback to cache or change state
            return
        } catch {
            if Task.isCancelled { return }
            // 3. Last fallback: load the file Data in a background thread to avoid blocking MainActor,
            // then instantiate the NSImage on the Main Actor.
            let fallbackTask = Task.detached(priority: .userInitiated, operation: {
                if Task.isCancelled { throw CancellationError() }
                return try Data(contentsOf: url)
            })

            do {
                let data = try await withTaskCancellationHandler {
                    try await fallbackTask.value
                } onCancel: {
                    fallbackTask.cancel()
                }

                if Task.isCancelled { return }
                if let nsImage = NSImage(data: data) {
                    let cost = Self.cost(for: nsImage)
                    Self.cache.setObject(nsImage, forKey: url.standardizedFileURL as NSURL, cost: cost)
                    image = nsImage
                    loadedURL = url
                }
            } catch {
                // Ignore errors
            }
        }
    }
}
