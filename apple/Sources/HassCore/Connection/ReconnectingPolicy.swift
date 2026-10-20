import Foundation

/// When the quiet "Reconnecting…" chip shows (owner, 2026-10-17; `.agents/platforms/apple/connection-lifecycle.md`).
///
/// A socket that is down for a moment (a Wi-Fi to cellular hand-off, the app coming back from the background) is not worth
/// mentioning: the chip waits until the connection has been down for ``delay``, and goes as soon as it is live again. The values
/// on screen stay either way; the chip is the only sign.
public enum ReconnectingPolicy {
    /// How long the connection must have been down before the chip shows.
    public static let delay: Duration = .seconds(2)

    /// Whether `status` is a connection that is not live and is not being refused: starting, waiting to retry, or closed.
    /// A refused token ends the session instead (the sign-in screen), so it never shows the chip.
    public static func isDown(_ status: HassConnection.Status) -> Bool {
        switch status {
        case .connected, .rejected: false
        case .disconnected, .connecting, .waitingToReconnect: true
        }
    }
}
