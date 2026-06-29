//
//  IOSurfaceMetalRenderer.swift
//  DuckSort
//
//  Zero-copy hardware memory mapping renderer. Wraps CVPixelBuffer and IOSurface
//  buffers directly into Metal texture VRAM for high-performance zero-copy rendering.
//

import Foundation
import Metal
import CoreVideo
import AppKit

final class IOSurfaceMetalRenderer: Sendable {
    static let shared = IOSurfaceMetalRenderer()

    private let device: MTLDevice?

    private init() {
        self.device = MTLCreateSystemDefaultDevice()
    }

    /// Wraps a CVPixelBuffer backed by an IOSurface into a Metal texture without CPU copy memory overhead.
    func makeTexture(from pixelBuffer: CVPixelBuffer) -> MTLTexture? {
        guard let device = device else { return nil }

        var textureCache: CVMetalTextureCache?
        guard CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache) == kCVReturnSuccess,
              let cache = textureCache else {
            return nil
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        var cvTexture: CVMetalTexture?
        let result = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            cache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &cvTexture
        )

        guard result == kCVReturnSuccess, let cvTexture = cvTexture else {
            return nil
        }

        return CVMetalTextureGetTexture(cvTexture)
    }
}
