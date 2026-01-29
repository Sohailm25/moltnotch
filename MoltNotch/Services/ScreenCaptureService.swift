// ABOUTME: Screen capture service using ScreenCaptureKit for full-screen screenshots.
// ABOUTME: Produces JPEG-encoded data with configurable downscaling for transmission.

import AppKit
import Foundation
import ScreenCaptureKit

enum ScreenCaptureService {

    static func hasPermission() -> Bool {
        return CGPreflightScreenCaptureAccess()
    }

    static func requestPermission() {
        CGRequestScreenCaptureAccess()
    }

    /// Captures the main display as a CGImage using ScreenCaptureKit.
    static func captureMainDisplay() async -> CGImage? {
        let permitted = hasPermission()
        #if DEBUG
        NSLog("[ScreenCapture] captureMainDisplay called. hasPermission=\(permitted)")
        #endif
        guard permitted else { return nil }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else {
                #if DEBUG
                NSLog("[ScreenCapture] No displays found")
                #endif
                return nil
            }

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.width = display.width
            config.height = display.height
            config.showsCursor = false

            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )
            #if DEBUG
            NSLog("[ScreenCapture] Capture succeeded: \(image.width)x\(image.height)")
            #endif
            return image
        } catch {
            #if DEBUG
            NSLog("[ScreenCapture] Capture FAILED: \(error)")
            #endif
            return nil
        }
    }

    /// Encodes a CGImage as JPEG data, downscaling if needed.
    static func encodeForTransmission(_ cgImage: CGImage, maxWidth: CGFloat = 1920, jpegQuality: CGFloat = 0.7) -> Data? {
        var image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))

        if CGFloat(cgImage.width) > maxWidth {
            let scale = maxWidth / CGFloat(cgImage.width)
            let newSize = NSSize(
                width: CGFloat(cgImage.width) * scale,
                height: CGFloat(cgImage.height) * scale
            )
            let resized = NSImage(size: newSize)
            resized.lockFocus()
            image.draw(in: NSRect(origin: .zero, size: newSize),
                       from: NSRect(origin: .zero, size: image.size),
                       operation: .copy,
                       fraction: 1.0)
            resized.unlockFocus()
            image = resized
        }

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg,
                                                    properties: [.compressionFactor: jpegQuality]) else {
            return nil
        }

        let twoMB = 2 * 1024 * 1024
        if jpegData.count > twoMB {
            return bitmap.representation(using: .jpeg,
                                          properties: [.compressionFactor: 0.4])
        }

        return jpegData
    }

    /// Captures, encodes, and returns JPEG data ready for transmission.
    static func captureForTransmission(maxWidth: CGFloat = 1920, jpegQuality: CGFloat = 0.7) async -> Data? {
        guard let cgImage = await captureMainDisplay() else { return nil }
        return encodeForTransmission(cgImage, maxWidth: maxWidth, jpegQuality: jpegQuality)
    }

    /// Captures a screenshot and returns it as a base64-encoded JPEG string.
    static func captureAsBase64(maxWidth: CGFloat = 1920, jpegQuality: CGFloat = 0.7) async -> String? {
        guard let data = await captureForTransmission(maxWidth: maxWidth, jpegQuality: jpegQuality) else {
            return nil
        }
        return data.base64EncodedString()
    }
}
