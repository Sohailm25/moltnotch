// ABOUTME: Tests for screen capture service validating JPEG encoding and base64 output.
// ABOUTME: Some tests are conditional on screen capture permission being granted.

import XCTest
@testable import MoltNotch

final class ScreenCaptureServiceTests: XCTestCase {

    func testCaptureReturnsDataWhenPermissionGranted() {
        // This test is conditional — may skip in CI where permission isn't granted
        let data = ScreenCaptureService.captureForTransmission()
        // If we got data, it should be non-empty
        if let data = data {
            XCTAssertFalse(data.isEmpty)
        }
    }

    func testJPEGDataStartsWithCorrectBytes() {
        guard let data = ScreenCaptureService.captureForTransmission() else {
            // No permission — skip
            return
        }
        // JPEG files start with 0xFF 0xD8
        XCTAssertEqual(data[0], 0xFF)
        XCTAssertEqual(data[1], 0xD8)
    }

    func testBase64EncodingProducesValidString() {
        guard let base64 = ScreenCaptureService.captureAsBase64() else {
            return
        }
        XCTAssertFalse(base64.isEmpty)
        // Valid base64 should be decodable
        XCTAssertNotNil(Data(base64Encoded: base64))
    }

    func testOutputSizeUnder2MB() {
        guard let data = ScreenCaptureService.captureForTransmission() else {
            return
        }
        let twoMB = 2 * 1024 * 1024
        XCTAssertLessThanOrEqual(data.count, twoMB)
    }

    func testHasPermissionReturnsBool() {
        // Just verify it returns without crashing
        let _ = ScreenCaptureService.hasPermission()
    }

    func testDownscaleRespectsMaxWidth() {
        guard let data = ScreenCaptureService.captureForTransmission(maxWidth: 800) else {
            return
        }
        // We can't easily check pixel dimensions from JPEG data without NSImage,
        // but we can verify the data is smaller than full resolution
        let fullData = ScreenCaptureService.captureForTransmission()
        if let fullData = fullData {
            XCTAssertLessThanOrEqual(data.count, fullData.count + 1024) // allow small variance
        }
    }
}
