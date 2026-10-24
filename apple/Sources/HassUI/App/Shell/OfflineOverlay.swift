import HassCore
import HassDesign
import SwiftUI

/// Shows ``OfflineChip`` under the header while the device has no network path, and removes it when one returns. Without a
/// connection (galleries, previews) it shows nothing. A connection that is retrying with a path is not offline: it shows the
/// header's ``ReconnectingArc`` (``ReconnectingIndicator``).
struct OfflineOverlay: ViewModifier {
    /// Where the header ends; the chip sits just under it, at the trailing edge, clear of a large title.
    var headerEnd: CGFloat
    /// Overrides the connection's own offline state (hosted tests).
    var offlineOverride: Bool?

    @Environment(HassConnection.self) private var connection: HassConnection?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isOffline: Bool { offlineOverride ?? connection?.isOffline ?? false }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topTrailing) {
                if isOffline {
                    OfflineChip()
                        .padding(.top, headerEnd + HassTokens.Spacing.xs)
                        .padding(.trailing, HassTokens.Spacing.l)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(reduceMotion ? MotionTokens.crossFade : MotionTokens.standard, value: isOffline)
    }
}

extension View {
    /// The offline chip under a header that ends `headerEnd` points down.
    func offlineChip(headerEnd: CGFloat) -> some View {
        modifier(OfflineOverlay(headerEnd: headerEnd))
    }
}
