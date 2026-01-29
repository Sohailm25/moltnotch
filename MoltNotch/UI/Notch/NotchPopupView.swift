// ABOUTME: SwiftUI view wrapping content with NotchShape mask and frame-based emergence animation.
// ABOUTME: The mask animates from notch-size to full content size, creating a "notch expanding" effect.

import SwiftUI

struct NotchPopupView<Content: View>: View {
    let hasNotch: Bool
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let content: Content

    @State private var isExpanded = false

    private let willHide = NotificationCenter.default.publisher(for: .notchPanelWillHide)
    private let willShow = NotificationCenter.default.publisher(for: .notchPanelWillShow)

    init(
        hasNotch: Bool,
        notchWidth: CGFloat,
        notchHeight: CGFloat,
        @ViewBuilder content: () -> Content
    ) {
        self.hasNotch = hasNotch
        self.notchWidth = notchWidth
        self.notchHeight = notchHeight
        self.content = content()
    }

    private var minWidth: CGFloat {
        notchWidth + (topCornerRadius * 2)
    }

    private var topCornerRadius: CGFloat {
        isExpanded ? Constants.notchExpandedTopRadius : Constants.notchClosedTopRadius
    }

    private var bottomCornerRadius: CGFloat {
        isExpanded ? Constants.notchExpandedBottomRadius : Constants.notchClosedBottomRadius
    }

    var body: some View {
        notchContent()
            .background {
                Rectangle()
                    .foregroundStyle(.black)
                    .padding(-50)
            }
            .mask {
                NotchShape(
                    topCornerRadius: topCornerRadius,
                    bottomCornerRadius: bottomCornerRadius
                )
                .padding(.horizontal, 0.5)
                .frame(
                    width: !isExpanded ? minWidth : nil,
                    height: !isExpanded ? notchHeight : nil
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .shadow(color: .black.opacity(isExpanded ? 0.5 : 0), radius: 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .task {
                withAnimation(.spring(duration: animationDuration, bounce: 0.35)) {
                    isExpanded = true
                }
            }
            .onReceive(willHide) { _ in
                withAnimation(.smooth(duration: animationDuration)) {
                    isExpanded = false
                }
            }
            .onReceive(willShow) { _ in
                withAnimation(.spring(duration: animationDuration, bounce: 0.35)) {
                    isExpanded = true
                }
            }
            .foregroundStyle(.white)
            .preferredColorScheme(.dark)
            .ignoresSafeArea()
    }

    private func notchContent() -> some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: notchHeight)
            content
        }
        .padding(.horizontal, topCornerRadius)
        .fixedSize()
        .frame(minWidth: minWidth, minHeight: notchHeight)
    }

    private var animationDuration: Double {
        Double(Constants.notchAnimationDurationInMilliseconds) / 1000.0
    }
}
