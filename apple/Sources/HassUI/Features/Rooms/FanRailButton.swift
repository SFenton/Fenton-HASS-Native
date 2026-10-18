import HassCore
import HassDesign
import SwiftUI

/// One round button on the fan tile's rail.
///
/// Inactive: a translucent circle (white 12% on the dark off tile, black 18% on the lit teal tile) with a white glyph.
/// Active (the fan is on, or locked): a solid white circle with the glyph in the tile's dark teal. The circle scales
/// with Dynamic Type up to 1.5x and the glyph stays under half its width, so the glyph never outgrows the circle.
struct FanRailButton: View {
    var label: String
    var symbol: String
    var isOn: Bool
    /// Whether the tile behind the rail is the lit (filled) teal one.
    var tileIsLit: Bool
    var id: String
    var action: () -> Void

    @ScaledMetric(relativeTo: .body) private var scaledDiameter = HassTokens.minTarget
    @ScaledMetric(relativeTo: .body) private var scaledGlyph: CGFloat = 18

    /// The circle's diameter: 44 pt at the default size, never more than 66.
    var diameter: CGFloat { Self.diameter(scaled: scaledDiameter) }

    /// The glyph's point size: scales with text, but stays within 45% of the circle.
    var glyphSize: CGFloat { Self.glyphSize(scaled: scaledGlyph, diameter: diameter) }

    static func diameter(scaled: CGFloat) -> CGFloat {
        min(max(scaled, HassTokens.minTarget), HassTokens.minTarget * 1.5)
    }

    static func glyphSize(scaled: CGFloat, diameter: CGFloat) -> CGFloat {
        min(scaled, diameter * 0.45)
    }

    /// The circle's fill for a state: solid white when active, else the translucent disc for the tile behind it.
    static func fill(isOn: Bool, tileIsLit: Bool) -> Color {
        if isOn { return .white }
        return tileIsLit ? .black.opacity(0.18) : .white.opacity(0.12)
    }

    /// The glyph colour: the tile's dark teal on a white circle, white otherwise.
    static func ink(isOn: Bool) -> Color {
        isOn ? (ColorFamily.air.fill ?? Color(rgb: 0x006E62)) : .white
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: glyphSize, weight: .semibold))
                .foregroundStyle(Self.ink(isOn: isOn))
                .frame(width: diameter, height: diameter)
                .background(Self.fill(isOn: isOn, tileIsLit: tileIsLit), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
        .accessibilityIdentifier(id)
    }
}
