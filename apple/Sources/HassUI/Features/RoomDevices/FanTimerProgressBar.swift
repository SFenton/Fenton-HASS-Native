import HassDesign
import SwiftUI

/// A thin capsule bar in the timer orange. `fraction` is how much is left, 1 at the start of the timer. Decorative: the
/// countdown carries the value.
struct FanTimerProgressBar: View {
    var fraction: Double
    static let height: CGFloat = 6

    var body: some View {
        Capsule()
            .fill(HassTokens.Ink.timer.opacity(0.22))
            .frame(height: Self.height)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(HassTokens.Ink.timer)
                        .frame(width: proxy.size.width * min(1, max(0, fraction)))
                }
            }
            .accessibilityHidden(true)
    }
}
