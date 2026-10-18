import HassCore
import HassDesign
import SwiftUI

/// Shows ``ReconnectingChip`` under the header once the connection has been down for ``ReconnectingPolicy/delay``, and removes it
/// when the connection is live again. Without a connection (galleries, previews) it shows nothing.
struct ReconnectingOverlay: ViewModifier {
    /// Where the header ends; the chip sits just under it, at the trailing edge, clear of a large title.
    var headerEnd: CGFloat
    /// Overrides the connection's own status (hosted tests).
    var statusOverride: HassConnection.Status?
    /// How long the connection must have been down before the chip shows (hosted tests shorten it).
    var delay: Duration = ReconnectingPolicy.delay

    @Environment(HassConnection.self) private var connection: HassConnection?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsChip = false

    private var isDown: Bool {
        guard let status = statusOverride ?? connection?.status else { return false }
        return ReconnectingPolicy.isDown(status)
    }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topTrailing) {
                if showsChip {
                    ReconnectingChip()
                        .padding(.top, headerEnd + HassTokens.Spacing.xs)
                        .padding(.trailing, HassTokens.Spacing.l)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(reduceMotion ? MotionTokens.crossFade : MotionTokens.standard, value: showsChip)
            // The chip waits out a short outage: a task per state, cancelled when the state changes.
            .task(id: isDown) {
                guard isDown else {
                    showsChip = false
                    return
                }
                guard (try? await Task.sleep(for: delay)) != nil else { return }
                showsChip = true
            }
    }
}

extension View {
    /// The "Reconnecting…" chip under a header that ends `headerEnd` points down.
    func reconnectingChip(headerEnd: CGFloat) -> some View {
        modifier(ReconnectingOverlay(headerEnd: headerEnd, statusOverride: nil))
    }
}
