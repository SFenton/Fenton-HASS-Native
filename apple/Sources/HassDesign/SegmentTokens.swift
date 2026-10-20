import SwiftUI

public extension HassTokens.Surface {
    /// The chosen segment of a custom segmented row (the bathroom fan's timer lengths): the label colour's opposite,
    /// white on a dark sheet and near-black (`#1C1C1E`) on a light one, so the choice holds 3:1 or better against the
    /// cell in both appearances.
    static let selectedSegment = Color.adaptive(light: 0x1C1C1E, dark: 0xFFFFFF)

    /// Text on ``selectedSegment``: black on white, white on near-black.
    static let selectedSegmentInk = Color.adaptive(light: 0xFFFFFF, dark: 0x000000)
}
