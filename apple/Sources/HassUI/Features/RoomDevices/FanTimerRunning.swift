import HassCore
import HassDesign
import SwiftUI

/// A running timer: a timer glyph and the countdown, both 40 pt in the web's timer orange, a thin progress bar that
/// empties as the time runs out, and Clear Timer as a red tinted capsule. No subtitle under the countdown.
struct FanTimerRunning: View {
    @Bindable var controller: BathroomFanController
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 40

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = controller.remainingSeconds(at: context.date)
            VStack(alignment: .leading, spacing: HassTokens.Spacing.m) {
                HStack(spacing: HassTokens.Spacing.m) {
                    Image(systemName: "timer")
                        .font(.system(size: size))
                        .accessibilityHidden(true)
                    Text(remaining.map(BathroomFanController.formatRemaining) ?? "Unavailable")
                        .font(.system(size: size, weight: .semibold).monospaced())
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                .foregroundStyle(HassTokens.Ink.timer)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Timer")
                .accessibilityValue(remaining.map(BathroomFanController.spokenRemaining) ?? "Unavailable")
                .accessibilityIdentifier("fan.remaining")

                FanTimerProgressBar(fraction: controller.remainingFraction(at: context.date) ?? 0)

                Button("Clear Timer", role: .destructive) { controller.cancelTimer() }
                    .buttonStyle(TintedCapsuleButtonStyle(tint: HassTokens.Ink.danger))
                    .disabled(!controller.timerAvailable)
                    .accessibilityIdentifier("fan.clearTimer")
            }
        }
    }
}
