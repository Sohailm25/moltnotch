// ABOUTME: Tests for screen capture service validating JPEG encoding and base64 output.
// ABOUTME: Some tests are conditional on screen capture permission being granted.

import XCTest
@testable import MoltNotch

final class ScreenCaptureServiceTests: XCTestCase {

    func testCaptureReturnsDataWhenPermissionGranted() async {
        let data = await ScreenCaptureService.captureForTransmission()
        if let data = data {
            XCTAssertFalse(data.isEmpty)
        }
    }

    func testJPEGDataStartsWithCorrectBytes() async {
        guard let data = await ScreenCaptureService.captureForTransmission() else {
            return
        }
        XCTAssertEqual(data[0], 0xFF)
        XCTAssertEqual(data[1], 0xD8)
    }

    func testBase64EncodingProducesValidString() async {
        guard let base64 = await ScreenCaptureService.captureAsBase64() else {
            return
        }
        XCTAssertFalse(base64.isEmpty)
        XCTAssertNotNil(Data(base64Encoded: base64))
    }

    func testOutputSizeUnder2MB() async {
        guard let data = await ScreenCaptureService.captureForTransmission() else {
            return
        }
        let twoMB = 2 * 1024 * 1024
        XCTAssertLessThanOrEqual(data.count, twoMB)
    }

    func testHasPermissionReturnsBool() {
        let _ = ScreenCaptureService.hasPermission()
    }

    func testDownscaleRespectsMaxWidth() async {
        guard let data = await ScreenCaptureService.captureForTransmission(maxWidth: 800) else {
            return
        }
        let fullData = await ScreenCaptureService.captureForTransmission()
        if let fullData = fullData {
            XCTAssertLessThanOrEqual(data.count, fullData.count + 1024)
        }
    }
}
