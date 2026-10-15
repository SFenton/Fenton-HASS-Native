import Foundation

/// In-memory ``PushRegistrationStore`` for tests and previews.
public final class InMemoryPushRegistrationStore: PushRegistrationStore, @unchecked Sendable {
    private let lock = NSLock()
    private var list = PushRegistrationList()

    /// Creates a store, optionally pre-filled.
    public init(_ registrations: [PushRegistration] = [], active: PushRegistration? = nil) {
        list = PushRegistrationList(registrations: registrations, active: active)
    }

    public func registration(server: HassServer, userID: String) -> PushRegistration? {
        lock.withLock { list.registration(server: server, userID: userID) }
    }

    public func save(_ registration: PushRegistration) { lock.withLock { list.save(registration) } }
    public func remove(server: HassServer, userID: String) { lock.withLock { list.remove(server: server, userID: userID) } }
    public var active: PushRegistration? { lock.withLock { list.active } }
    public func setActive(_ registration: PushRegistration?) { lock.withLock { list.active = registration } }
}
