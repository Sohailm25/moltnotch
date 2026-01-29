// ABOUTME: Unit tests for NotchDetector geometry calculations and screen utilities.
// ABOUTME: Validates fallback dimensions, mouse cursor detection, and notch size computation.

import XCTest
@testable import MoltNotch

final class NotchDetectorTests: XCTestCase {

    func testFallbackSizeMatchesConstants() {
        let fallback = NotchDetector.fallbackSize
        XCTAssertEqual(fallback.width, 300.0)
        XCTAssertEqual(fallback.height, 24.0)
    }

    func testScreenWithMouseCursorReturnsScreen() {
        let screen = NotchDetector.screenWithMouseCursor()
        XCTAssertNotNil(screen, "screenWithMouseCursor should return a screen on any Mac")
    }

    func testNotchSizeReturnsNonZero() {
        guard let screen = NSScreen.main else {
            XCTFail("No main screen available")
            return
        }
        let size = screen.notchSize
        XCTAssertGreaterThan(size.width, 0)
        XCTAssertGreaterThan(size.height, 0)
    }

    func testNotchFrameContainedInScreenFrame() {
        guard let screen = NSScreen.main else {
            XCTFail("No main screen available")
            return
        }
        let notchFrame = screen.notchFrame
        let screenFrame = screen.frame
        XCTAssertTrue(
            screenFrame.contains(notchFrame) || !screen.hasNotch,
            "Notch frame should be within screen frame on notched displays"
        )
    }

    func testNotchCenterXMatchesScreenMidX() {
        guard let screen = NSScreen.main else {
            XCTFail("No main screen available")
            return
        }
        let center = screen.notchCenter
        XCTAssertEqual(center.x, screen.frame.midX, accuracy: 1.0)
    }

    func testIsBuiltInDisplayReturnsBool() {
        guard let screen = NSScreen.main else {
            XCTFail("No main screen available")
            return
        }
        _ = NotchDetector.isBuiltInDisplay(screen)
    }

    func testHasNotchConsistentWithSafeAreaInsets() {
        guard let screen = NSScreen.main else {
            XCTFail("No main screen available")
            return
        }
        if screen.safeAreaInsets.top == 0 {
            XCTAssertFalse(screen.hasNotch)
        } else {
            XCTAssertTrue(screen.hasNotch)
        }
    }
}
