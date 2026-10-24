import HassCore
import SwiftUI

/// Runs a ``ReconnectingIndicator`` from the connection and shares it with every page's header: one instance, so a page pushed in
/// the middle of an outage already shows the arc. The arc follows a connection that is retrying with a network path; with no
/// path the app is offline and the offline chip speaks (``OfflineOverlay``).
struct ReconnectingIndicatorHost: ViewModifier {
    /// Overrides the connection's own status (hosted tests).
    var statusOverride: HassConnection.Status?
    /// Overrides the connection's own offline state (hosted tests).
    var offlineOverride: Bool?
    /// How long the connection must have been down before the arc shows (hosted tests shorten it).
    var delay: Duration = ReconnectingPolicy.delay

    @Environment(HassConnection.self) private var connection: HassConnection?
    @State private var indicator = ReconnectingIndicator()

    private var isRetrying: Bool {
        guard let status = statusOverride ?? connection?.status else { return false }
        return ReconnectingPolicy.showsReconnecting(status, isOffline: offlineOverride ?? connection?.isOffline ?? false)
    }

    func body(content: Content) -> some View {
        content
            .environment(indicator)
            // A task per state, cancelled when the state changes: a blip never shows the arc, and coming back mid-fade-out
            // lights it again where it is.
            .task(id: isRetrying) { await indicator.follow(isDown: isRetrying, delay: delay) }
    }
}

extension View {
    /// Shows the reconnecting arc in every header below this view while the connection is retrying.
    func reconnectingIndicator() -> some View {
        modifier(ReconnectingIndicatorHost())
    }
}
