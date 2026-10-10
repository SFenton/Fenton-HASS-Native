import Foundation

/// Maps app scene phases to connection actions so reopening the app never reloads it.
///
/// See `.agents/platforms/apple/connection-lifecycle.md`.
@MainActor
public final class ConnectionLifecycle {
    /// How long the socket stays open after the app leaves the foreground.
    public static let backgroundGrace: Duration = .seconds(30)

    private let connection: HassConnection
    private var disconnectTask: Task<Void, Never>?

    /// Creates a lifecycle controller for a connection.
    public init(connection: HassConnection) {
        self.connection = connection
    }

    /// The app became active: cancel any pending disconnect and make sure we're connected.
    public func didBecomeActive() {
        disconnectTask?.cancel()
        disconnectTask = nil
        connection.connect()
    }

    /// The app went to the background: save now, disconnect after the grace period.
    public func didEnterBackground() {
        connection.saveSnapshotNow()
        disconnectTask?.cancel()
        disconnectTask = Task { [connection] in
            try? await Task.sleep(for: Self.backgroundGrace)
            guard !Task.isCancelled else { return }
            connection.disconnect()
        }
    }
}
