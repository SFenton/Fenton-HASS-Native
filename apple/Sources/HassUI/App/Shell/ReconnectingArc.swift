import Foundation
import HassCore
import HassDesign
import SwiftUI

/// The reconnecting sign: a 20 pt white arc spinner in the header, left of Quick Links, that fades in once the connection has
/// been down for ``ReconnectingPolicy/delay`` and fades out when it is live again (owner, 2026-10-23, replacing the
/// "Reconnecting…" chip; `.agents/design/reconnecting-spinner.md`). No text: it is a status, so it has no tap action, and
/// VoiceOver reads its label.
///
/// ``ReconnectingIndicator`` decides when the arc is a bar item and when it is lit. The arc fades to `isLit` with a cross-fade
/// (opacity is not motion, so Reduce Motion keeps it; the spinner itself turns at half speed then, like every ``ArcSpinner``).
struct ReconnectingArc: View {
    /// What VoiceOver says.
    static let label = "Reconnecting to Home Assistant"

    /// How the arc sits in the bar.
    enum Metrics {
        /// The arc's diameter (``ArcSpinner/Size/compact``).
        static let diameter: CGFloat = 20
        /// The narrowest cell the bar gives a bar item (44 pt), which centres the arc: measured on the iPhone 17 Pro simulator
        /// (iOS 27), an arc with its trailing padding cancelled sat 19 pt from Quick Links, not 12, because the cell was 44 wide.
        static let cellWidth: CGFloat = HassTokens.minTarget

        /// How far the arc is drawn right of the middle of its cell so it ends at the cell's trailing edge, the way Profile's
        /// disc fills its cell: the gap to Quick Links is then the bar's own spacer, the same as Quick Links to Profile.
        ///
        /// On iOS 26.5 the bar gives Profile's hidden-glass cell 8 pt more, so Quick Links to Profile is 16 pt there
        /// (`direction-g.md`, "iOS 26.5 differs"); measured on the iPad simulator (26.5), the arc then sat 12 pt from Quick Links,
        /// so it is drawn 4 pt less far right to match.
        static var trailingShift: CGFloat {
            let base = (cellWidth - diameter) / 2
            return ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0))
                ? base : base - 4
        }
    }

    let indicator: ReconnectingIndicator
    /// Quick Links follows the arc in the bar, so the arc is drawn to the trailing edge of its cell to sit Quick Links' gap away
    /// (iOS 26 and later, where the bar sizes the cell). On the Duo's rail the arc is alone in the page header and stays centred.
    let besideQuickLinks: Bool
    @State private var lit: Bool

    init(indicator: ReconnectingIndicator, besideQuickLinks: Bool = true) {
        self.indicator = indicator
        self.besideQuickLinks = besideQuickLinks
        // Starts as the indicator is, so a page that appears mid-outage shows a lit arc at once; only a change fades.
        _lit = State(initialValue: indicator.isLit)
    }

    var body: some View {
        ArcSpinner(.compact, label: Self.label)
            .foregroundStyle(.white)
            .opacity(lit ? 1 : 0)
            .animation(MotionTokens.crossFade, value: lit)
            .onChange(of: indicator.isLit) { _, isLit in lit = isLit }
            .modifier(TrailingEdge(applies: besideQuickLinks))
            .accessibilityIdentifier("reconnecting.arc")
    }
}

/// Draws the arc at the trailing edge of its 44 pt bar cell (iOS 26 and later); before iOS 26 the bar draws no glass and sizes the
/// cell to the arc, so there is nothing to shift.
private struct TrailingEdge: ViewModifier {
    var applies: Bool

    func body(content: Content) -> some View {
        if applies, #available(iOS 26.0, macOS 26.0, *) {
            content.offset(x: ReconnectingArc.Metrics.trailingShift)
        } else {
            content
        }
    }
}
