// ABOUTME: NSScreen extension for notch detection and geometry calculation.
// ABOUTME: Provides notch presence, size, frame, center, and mouse-cursor screen utility.

import AppKit

extension NSScreen {
    var hasNotch: Bool {
        safeAreaInsets.top != 0
    }

    var notchSize: CGSize {
        guard safeAreaInsets.top > 0,
              let left = auxiliaryTopLeftArea?.width,
              let right = auxiliaryTopRightArea?.width,
              left > 0, right > 0
        else {
            return NotchDetector.fallbackSize
        }
        return CGSize(
            width: frame.width - left - right,
            height: safeAreaInsets.top
        )
    }

    var notchFrame: CGRect {
        let size = notchSize
        let x = frame.midX - size.width / 2
        let y = frame.maxY - size.height
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    var notchCenter: CGPoint {
        CGPoint(x: frame.midX, y: frame.maxY - safeAreaInsets.top / 2)
    }
}

enum NotchDetector {
    static let fallbackSize = CGSize(
        width: Constants.notchFallbackWidth,
        height: Constants.notchFallbackHeight
    )

    static func screenWithMouseCursor() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
    }

    static func isBuiltInDisplay(_ screen: NSScreen) -> Bool {
        let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
        return CGDisplayIsBuiltin(screenNumber) != 0
    }
}
