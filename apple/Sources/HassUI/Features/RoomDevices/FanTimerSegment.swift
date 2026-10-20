import HassCore
import HassDesign
import SwiftUI

/// One length in the row: a 44 pt target, filled when chosen.
struct FanTimerSegment: View {
    var minutes: Int
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(BathroomFanController.segmentTitle(minutes))
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(isSelected ? HassTokens.Surface.selectedSegmentInk : HassTokens.Ink.primary)
                .frame(maxWidth: .infinity, minHeight: HassTokens.minTarget)
                .background {
                    if isSelected { RoundedRectangle(cornerRadius: 10, style: .continuous).fill(HassTokens.Surface.selectedSegment) }
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(BathroomFanController.durationTitle(minutes))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("fan.timerOption.\(minutes)")
    }
}
