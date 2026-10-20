import HassCore
import HassDesign
import SwiftUI

/// The six timer lengths as a segmented row (5m, 10m, 15m, 20m, 30m, 1h): 44 pt tall, the chosen one filled with the
/// label's opposite (white with black text on a dark sheet; near-black with white text on a light one, which keeps the
/// choice at 3:1 or better against the cell). At accessibility sizes the row wraps to three columns.
struct FanTimerLengthRow: View {
    @Binding var selection: Int
    @Environment(\.dynamicTypeSize) private var typeSize

    /// The lengths offered (`BathroomFanController.timerMinutes`).
    var lengths: [Int] = BathroomFanController.timerMinutes

    private var segments: some View {
        ForEach(lengths, id: \.self) { minutes in
            FanTimerSegment(minutes: minutes, isSelected: minutes == selection) { selection = minutes }
        }
    }

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3), spacing: 2) { segments }
            } else {
                HStack(spacing: 2) { segments }
            }
        }
        .padding(2)
        .background(HassTokens.Surface.sheetCell, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fan.timerLength")
    }
}
