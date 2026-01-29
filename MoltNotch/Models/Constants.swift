// ABOUTME: Shared constants for notch panel geometry and animation. Ported from Barik.
// ABOUTME: Defines fallback dimensions and corner radii for open/closed notch states.

import CoreFoundation

struct Constants {
    static let notchAnimationDurationInMilliseconds = 400
    static let notchFallbackWidth: CGFloat = 300.0
    static let notchFallbackHeight: CGFloat = 24.0
    static let notchClosedTopRadius: CGFloat = 6.0
    static let notchClosedBottomRadius: CGFloat = 14.0
    static let notchExpandedTopRadius: CGFloat = 15.0
    static let notchExpandedBottomRadius: CGFloat = 24.0
}
