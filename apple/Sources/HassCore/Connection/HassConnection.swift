import Foundation
@preconcurrency import HAKit
import HassTelemetry
import Observation

/// The app's one Home Assistant connection: a HAKit websocket feeding ``EntityStore``.
///
/// Views never touch HAKit. They read the store and act through ``callService(_:_:data:)``.
@MainActor
@Observable
public final class HassConnection {
    // MARK: - Types

    /// Connection status for the UI.
    public enum Status: Equatable, Sendable {
        case disconnected
        case connecting
        case connected(version: String)
        case waitingToReconnect
        /// The server rejected the token; the user must sign in again.
        case rejected
    }

    /// Posted (on the main actor, object: the connection) each time the socket becomes ready for commands, including
    /// after a reconnect. Camera streams that gave up while the socket was down restart on it.
    public static let didBecomeReadyNotification = Notification.Name("HassConnection.didBecomeReady")

    // MARK: - Public state

    /// Current status.
    public private(set) var status: Status = .disconnected

    /// The server this connection talks to.
    public let server: HassServer

    /// Moves the websocket to Home Assistant's home network address when the phone is at home; nil keeps the
    /// public URL (tests, extensions).
    public let route: LocalServerRoute?

    /// The entity store this connection feeds.
    public let store: EntityStore

    // MARK: - Private

    @ObservationIgnored let connection: HAConnection
    @ObservationIgnored private let snapshotCache: EntitySnapshotCache
    @ObservationIgnored private var statesSubscription: HACancellable?
    // Read in `deinit`, which is nonisolated; only the main actor writes it.
    @ObservationIgnored nonisolated(unsafe) private var stateObserver: NSObjectProtocol?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    /// The HAKit entities last diffed, so each delivery converts only what changed. Touched only on ``deltaQueue``.
    @ObservationIgnored nonisolated(unsafe) private var lastDelivered: [String: HAEntity] = [:]
    /// The newest delivery not yet diffed (``receive(_:)``). Touched only on ``deltaQueue``.
    @ObservationIgnored nonisolated(unsafe) private var pendingDelivery: Delivery?
    /// HAKit's callback queue, in place of the main queue. HAKit rebuilds its whole set of entities (thousands) on every
    /// change and hands it over, and the diff against the last set hashes and compares them all again: together over
    /// half of the main thread's CPU time, about 9 ms per delivery several times a second, longer than a 120 Hz frame
    /// (`.agents/testing/apple/performance.md`, "Scroll cost"). Both now run here and only the changed entities
    /// reach the main thread.
    @ObservationIgnored private let deltaQueue = DispatchQueue(label: "com.sfenton.home.entity-delta", qos: .userInitiated)
    /// The app wants the socket open (between ``connect(subscribingToStates:)`` and ``disconnect()``).
    @ObservationIgnored var wantsConnection = false
    @ObservationIgnored private var routeTask: Task<Void, Never>?
    /// Gauges for what this connection registers (`ResourceCensus`).
    @ObservationIgnored private var census: ResourceCensus.Registration?

    /// How long live updates are batched before the disk snapshot is rewritten.
    static let snapshotDebounce: Duration = .seconds(10)

    // MARK: - Init

    /// Creates a connection and restores the disk snapshot into the store before any network work.
    /// - Parameters:
    ///   - server: The server to connect to.
    ///   - tokens: Supplies access tokens.
    ///   - store: The store to feed.
    ///   - snapshotCache: Disk snapshot of entity states.
    ///   - route: Uses the home network address at home (``LocalServerRoute``); nil always uses the public URL.
    public convenience init(server: HassServer, tokens: TokenManager, store: EntityStore, snapshotCache: EntitySnapshotCache = .init(),
                            route: LocalServerRoute? = nil) {
        let configuration = HAConnectionConfiguration(
            connectionInfo: { HassConnection.connectionInfo(server: server, route: route) },
            fetchAuthToken: { completion in
                nonisolated(unsafe) let completion = completion
                Task {
                    do {
                        completion(.success(try await tokens.validAccessToken()))
                    } catch {
                        completion(.failure(error))
                    }
                }
            }
        )
        self.init(
            server: server, store: store, snapshotCache: snapshotCache,
            connection: HAKit.connection(configuration: configuration, connectAutomatically: false),
            route: route
        )
    }

    /// Creates a connection over a given HAKit connection (tests pass `HAMockConnection`).
    init(server: HassServer, store: EntityStore, snapshotCache: EntitySnapshotCache = .init(), connection: HAConnection,
         route: LocalServerRoute? = nil) {
        self.server = server
        self.store = store
        self.snapshotCache = snapshotCache
        self.connection = connection
        self.route = route
        connection.callbackQueue = deltaQueue

        if let snapshot = snapshotCache.load(for: server) {
            store.replaceAll(snapshot.entities, freshness: .snapshot(savedAt: snapshot.savedAt))
        }

        stateObserver = NotificationCenter.default.addObserver(
            forName: HAConnectionState.didTransitionToStateNotification,
            object: connection,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshStatus() }
        }

        route?.startWatching { [weak self] in
            Task { @MainActor in self?.networkDidChange() }
        }

        census = ResourceCensus.shared.register { [weak self] in self?.liveResources ?? [:] }
    }

    /// What this connection has registered right now (`ResourceCensus`): each is 0 or 1, and a resume leaves them as
    /// they were.
    var liveResources: [String: Int] {
        [
            "Connection.statesSubscription": statesSubscription == nil ? 0 : 1,
            "Connection.stateObserver": stateObserver == nil ? 0 : 1,
            "Connection.saveTask": saveTask == nil ? 0 : 1,
            "Connection.routeTask": routeTask == nil ? 0 : 1,
        ]
    }

    deinit {
        // A block observer stays registered until it is removed; dropping the token would leave it behind.
        if let stateObserver { NotificationCenter.default.removeObserver(stateObserver) }
    }

    /// Where HAKit connects: the route's current URL (HAKit reads this on every connect and swaps the socket
    /// only when the URL changed).
    nonisolated static func connectionInfo(server: HassServer, route: LocalServerRoute?) -> HAConnectionInfo? {
        try? HAConnectionInfo(url: route?.currentURL ?? server.baseURL, userAgent: "FentonHome")
    }

    // MARK: - Lifecycle

    /// Opens the websocket and subscribes to entity states. Safe to call repeatedly.
    /// - Parameter subscribingToStates: Also subscribe to every entity's state. A notification extension that only
    ///   sends a command (a camera's stream) passes false, so it stays inside its memory limit.
    public func connect(subscribingToStates: Bool = true) {
        wantsConnection = true
        connection.connect()
        refreshRoute()
        guard subscribingToStates, statesSubscription == nil else { return }
        statesSubscription = connection.caches.states().subscribe(Self.statesHandler(for: self))
    }

    /// Closes the websocket and saves the snapshot. The store keeps its values so the UI does not blank.
    public func disconnect() {
        wantsConnection = false
        routeTask?.cancel()
        routeTask = nil
        saveSnapshotNow()
        statesSubscription?.cancel()
        statesSubscription = nil
        connection.disconnect()
    }

    /// Saves the snapshot immediately (entering background).
    public func saveSnapshotNow() {
        saveTask?.cancel()
        saveTask = nil
        try? snapshotCache.save(Array(store.allValues.values), server: server)
    }

    // MARK: - Route

    /// Checks whether Home Assistant answers on the home network and moves the socket there, or back to the
    /// public URL. Runs on every connect and network change; the current socket keeps working meanwhile.
    public func refreshRoute() {
        guard let route else { return }
        routeTask?.cancel()
        let confirmHome: @Sendable () async -> Bool = { [weak self] in await self?.isHomeConfirmedOverPublicURL() ?? false }
        routeTask = Task { [weak self] in
            let changed = await route.refresh(confirmHome: confirmHome)
            guard changed, !Task.isCancelled else { return }
            self?.applyRoute()
        }
    }

    /// Whether Home Assistant says the signed-in person is home, from live states that came over the public URL.
    /// The route asks this only before it has pinned the server's instance id, so a network that merely advertises
    /// our server can't receive the token.
    func isHomeConfirmedOverPublicURL() async -> Bool {
        guard route?.isLocal == false, store.freshness == .live, let user = try? await currentUser() else { return false }
        // Re-checked after the await: the states must still be ones the public URL delivered.
        guard route?.isLocal == false else { return false }
        return store.allValues.values.contains { entity in
            entity.entityId.hasPrefix("person.") && entity.attributes["user_id"]?.string == user.id && entity.state == "home"
        }
    }

    /// A new network: stop using the home address at once (the next connect goes to the public URL), then look again.
    func networkDidChange() {
        if route?.reset() == true { applyRoute() }
        refreshRoute()
    }

    /// Reconnects on the route's current URL; the states subscription, the store and every view stay as they are.
    ///
    /// Disconnects first rather than letting `connect()` swap sockets: HAKit's swap leaves the old socket's delegate
    /// in place, so its late close event could tear down the new socket.
    private func applyRoute() {
        guard wantsConnection else { return }
        Telemetry.count(route?.isLocal == true ? "connection.route.local" : "connection.route.public")
        connection.disconnect()
        connection.connect()
    }

    // MARK: - Actions

    /// Calls a Home Assistant service.
    /// - Parameters:
    ///   - domain: e.g. `light`.
    ///   - service: e.g. `toggle`.
    ///   - data: Service data, including `entity_id`.
    public func callService(_ domain: String, _ service: String, data: [String: any Sendable] = [:]) async throws {
        let request = HATypedRequest<HAResponseVoid>.callService(
            domain: .init(rawValue: domain),
            service: .init(rawValue: service),
            data: data
        )
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(request) { @Sendable result in
                switch result {
                case .success: continuation.resume()
                case let .failure(error): continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Sends a light power or brightness command (``LightControl``).
    public func send(_ command: LightControl.Command) async throws {
        try await callService(command.domain, command.service, data: command.serviceData)
    }

    /// Convenience for `<domain>.toggle` on one entity. Not for lights: Presence Based Lighting reverts
    /// toggles in empty rooms, so lights use ``send(_:)`` with ``LightControl``.
    public func toggle(_ entityId: String) async throws {
        let domain = String(entityId.prefix { $0 != "." })
        try await callService(domain, "toggle", data: ["entity_id": entityId])
    }

    // MARK: - Cameras

    /// Asks Home Assistant for a camera's HLS stream (`camera/stream`).
    /// - Parameter entityId: The camera entity.
    /// - Returns: The tokenized playlist path, e.g. `/api/hls/<token>/master_playlist.m3u8`.
    public func cameraStreamPath(entityId: String) async throws -> String {
        try await requestString("camera/stream", data: ["entity_id": entityId, "format": "hls"], field: "url",
                                timeout: Self.streamCommandTimeout)
    }

    /// Signs a server path so a client without the auth header (a raw websocket) can open it (`auth/sign_path`).
    /// - Parameters:
    ///   - path: The path to sign, e.g. ``CameraStreamEndpoints/webRTCSocketPath``.
    ///   - expires: Seconds the signature stays valid; it is only checked when the path is opened.
    /// - Returns: The path with its `authSig` query.
    public func signPath(_ path: String, expires: Int = 30) async throws -> String {
        try await requestString("auth/sign_path", data: ["path": path, "expires": expires], field: "path",
                                timeout: Self.streamCommandTimeout)
    }

    /// How long a camera's stream commands may go unanswered. HAKit silently drops a command caught by a socket
    /// reset, so without this a camera started across a reconnect waited forever (owner report 2026-10-16).
    static let streamCommandTimeout: Duration = .seconds(10)

    /// Error for a websocket command whose result lacks the expected field.
    public struct UnexpectedResponse: Error, Equatable {
        /// The command that answered unexpectedly.
        public let command: String
    }

    // MARK: - Private

    /// Sends a websocket command once (no retry across reconnects) and returns one string field of its result.
    private func requestString(_ command: String, data: [String: any Sendable], field: String, timeout: Duration? = nil) async throws -> String {
        guard case let .dictionary(values) = try await sendCommand(command, data: data, timeout: timeout), let value = values[field] as? String else {
            throw UnexpectedResponse(command: command)
        }
        return value
    }

    /// One HAKit delivery: every entity the server has. HAKit's entities hold untyped attribute dictionaries, so the set is
    /// not `Sendable`; it is immutable here and only read on ``deltaQueue``.
    struct Delivery: @unchecked Sendable {
        var entities: Set<HAEntity>
    }

    /// What a delivery changed, ready to apply on the main thread.
    struct Applied: Sendable {
        var changed: [EntityState]
        var removed: [String]
        var isFirst: Bool
    }

    /// The states subscription's handler. Built outside the main actor on purpose: a closure written in ``connect(subscribingToStates:)``
    /// would inherit its isolation, and HAKit calls it on ``deltaQueue``, where Swift traps a main-actor closure.
    nonisolated private static func statesHandler(for connection: HassConnection) -> (HACancellable, HACachedStates) -> Void {
        { [weak connection] _, cached in connection?.receive(Delivery(entities: cached.all)) }
    }

    /// Keeps the newest delivery and schedules a pass behind whatever is queued, so a burst of changes is diffed once: every
    /// delivery is the whole set, and the newest says everything the older ones did. Runs on ``deltaQueue`` only.
    nonisolated func receive(_ delivery: Delivery) {
        pendingDelivery = delivery
        deltaQueue.async { [weak self] in
            guard let self, let latest = self.pendingDelivery else { return }
            self.pendingDelivery = nil
            self.process(latest)
        }
    }

    /// Diffs one HAKit delivery against the last and applies what changed on the main actor, in delivery order.
    /// Runs on ``deltaQueue`` only.
    nonisolated func process(_ delivery: Delivery) {
        let delta = Self.delta(from: lastDelivered, to: delivery.entities)
        lastDelivered = delta.delivered
        let applied = Applied(changed: delta.changed, removed: delta.removed, isFirst: delta.isFirst)
        DispatchQueue.main.async { MainActor.assumeIsolated { self.apply(applied) } }
    }

    /// Applies one delivery's changes to the store. The only part of a delivery that runs on the main thread.
    func apply(_ delta: Applied) {
        let interval = Telemetry.begin(Telemetry.Name.entityUpdate)
        if delta.isFirst {
            // The first live set replaces the disk snapshot, dropping entities the server no longer has.
            store.replaceAll(delta.changed, freshness: .live)
            // Live presence can now confirm home for a route that has not seen this server at home yet.
            if route?.isLocal == false { refreshRoute() }
        } else {
            store.apply(delta.changed, removing: delta.removed, freshness: .live)
        }
        Telemetry.end(interval, value: Double(delta.changed.count + delta.removed.count))
        Telemetry.count("entity.deliveries")
        Telemetry.count("entity.changed", by: delta.changed.count)
        scheduleSnapshotSave()
    }

    /// What changed between two HAKit deliveries.
    struct Delta {
        /// The new delivery keyed by entity id.
        var delivered: [String: HAEntity]
        /// Converted states for new or changed entities (every entity on the first delivery).
        var changed: [EntityState]
        /// Entity ids that disappeared.
        var removed: [String]
        /// No previous delivery: `changed` is the full set.
        var isFirst: Bool
    }

    /// Diffs `entities` against the previous delivery, converting only the entities that changed.
    nonisolated static func delta(from previous: [String: HAEntity], to entities: Set<HAEntity>) -> Delta {
        var delivered: [String: HAEntity] = [:]
        delivered.reserveCapacity(entities.count)
        var changed: [EntityState] = []
        for entity in entities {
            delivered[entity.entityId] = entity
            if previous[entity.entityId] != entity { changed.append(EntityState(haEntity: entity)) }
        }
        let removed = previous.isEmpty ? [] : previous.keys.filter { delivered[$0] == nil }
        return Delta(delivered: delivered, changed: changed, removed: removed, isFirst: previous.isEmpty)
    }

    private func scheduleSnapshotSave() {
        guard saveTask == nil else { return }
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: Self.snapshotDebounce)
            guard !Task.isCancelled, let self else { return }
            self.saveTask = nil
            // Encoding thousands of entities took tens of milliseconds on the main thread mid-scroll; only the
            // copy of the values happens here. Entering background still saves synchronously.
            let entities = Array(self.store.allValues.values)
            let cache = self.snapshotCache
            let server = self.server
            Task.detached(priority: .utility) {
                Telemetry.measure("SnapshotSave") { try? cache.save(entities, server: server) }
            }
        }
    }

    func refreshStatus() {
        let next: Status
        switch connection.state {
        case .connecting, .authenticating: next = .connecting
        case let .ready(version): next = .connected(version: version)
        case let .disconnected(reason):
            switch reason {
            case .disconnected: next = .disconnected
            case .rejected: next = .rejected
            case .waitingToReconnect:
                next = .waitingToReconnect
                // A failed socket on the home address falls back to the public URL for HAKit's retry.
                route?.reset()
            }
        }
        guard status != next else { return }
        let previous = status
        status = next
        PushTrace.shared.record("connection: \(previous) -> \(next)")
        if case .connected = next {
            NotificationCenter.default.post(name: Self.didBecomeReadyNotification, object: self)
        }
    }
}

extension EntityState {
    /// Converts a HAKit entity.
    init(haEntity entity: HAEntity) {
        self.init(
            entityId: entity.entityId,
            state: entity.state,
            attributes: entity.attributes.dictionary.mapValues { JSONValue(any: $0) },
            lastChanged: entity.lastChanged
        )
    }
}
