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

    static func captureForTransmission(maxWidth: CGFloat = 1920, jpegQuality: CGFloat = 0.7) -> Data? {
        guard hasPermission() else { return nil }

        guard let cgImage = captureMainDisplaySync() else { return nil }

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

    static func captureAsBase64(maxWidth: CGFloat = 1920, jpegQuality: CGFloat = 0.7) -> String? {
        debugLog("[ScreenCapture] captureAsBase64 called. hasPermission=\(hasPermission())")
        guard let data = captureForTransmission(maxWidth: maxWidth, jpegQuality: jpegQuality) else {
            debugLog("[ScreenCapture] captureForTransmission returned nil")
            return nil
        }
        debugLog("[ScreenCapture] got data, size=\(data.count) bytes")
        return data.base64EncodedString()
    }

    private static func debugLog(_ msg: String) {
        let line = "\(msg)\n"
        if let data = line.data(using: .utf8) {
            let fh = FileHandle(forWritingAtPath: "/tmp/barik-debug.log") ?? {
                FileManager.default.createFile(atPath: "/tmp/barik-debug.log", contents: nil)
                return FileHandle(forWritingAtPath: "/tmp/barik-debug.log")!
            }()
            fh.seekToEndOfFile()
            fh.write(data)
            fh.closeFile()
        }
    }

    // MARK: - ScreenCaptureKit synchronous bridge

    private static func captureMainDisplaySync() -> CGImage? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: CGImage?

        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first else {
                    semaphore.signal()
                    return
                }

                let filter = SCContentFilter(display: display, excludingWindows: [])
                let config = SCStreamConfiguration()
                config.width = display.width
                config.height = display.height
                config.showsCursor = false

                result = try await SCScreenshotManager.captureImage(
                    contentFilter: filter,
                    configuration: config
                )
            } catch {
                result = nil
            }
            semaphore.signal()
        }

        semaphore.wait()
        return result
    }
}
