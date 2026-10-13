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

    // MARK: - Public state

    /// Current status.
    public private(set) var status: Status = .disconnected

    /// The server this connection talks to.
    public let server: HassServer

    /// The entity store this connection feeds.
    public let store: EntityStore

    // MARK: - Private

    @ObservationIgnored let connection: HAConnection
    @ObservationIgnored private let snapshotCache: EntitySnapshotCache
    @ObservationIgnored private var statesSubscription: HACancellable?
    @ObservationIgnored private var stateObserver: NSObjectProtocol?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    /// The HAKit entities last applied, so each delivery converts only what changed.
    @ObservationIgnored private var lastDelivered: [String: HAEntity] = [:]

    /// How long live updates are batched before the disk snapshot is rewritten.
    static let snapshotDebounce: Duration = .seconds(10)

    // MARK: - Init

    /// Creates a connection and restores the disk snapshot into the store before any network work.
    /// - Parameters:
    ///   - server: The server to connect to.
    ///   - tokens: Supplies access tokens.
    ///   - store: The store to feed.
    ///   - snapshotCache: Disk snapshot of entity states.
    public convenience init(server: HassServer, tokens: TokenManager, store: EntityStore, snapshotCache: EntitySnapshotCache = .init()) {
        let baseURL = server.baseURL
        let configuration = HAConnectionConfiguration(
            connectionInfo: { try? HAConnectionInfo(url: baseURL, userAgent: "FentonHome") },
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
            connection: HAKit.connection(configuration: configuration, connectAutomatically: false)
        )
    }

    /// Creates a connection over a given HAKit connection (tests pass `HAMockConnection`).
    init(server: HassServer, store: EntityStore, snapshotCache: EntitySnapshotCache = .init(), connection: HAConnection) {
        self.server = server
        self.store = store
        self.snapshotCache = snapshotCache
        self.connection = connection

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
    }

    // MARK: - Lifecycle

    /// Opens the websocket and subscribes to entity states. Safe to call repeatedly.
    public func connect() {
        connection.connect()
        guard statesSubscription == nil else { return }
        statesSubscription = connection.caches.states().subscribe { [weak self] _, cached in
            let entities = cached.all
            MainActor.assumeIsolated { self?.receive(entities) }
        }
    }

    /// Closes the websocket and saves the snapshot. The store keeps its values so the UI does not blank.
    public func disconnect() {
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
            connection.send(request) { result in
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
        try await requestString("camera/stream", data: ["entity_id": entityId, "format": "hls"], field: "url")
    }

    /// Signs a server path so a client without the auth header (a raw websocket) can open it (`auth/sign_path`).
    /// - Parameters:
    ///   - path: The path to sign, e.g. ``CameraStreamEndpoints/webRTCSocketPath``.
    ///   - expires: Seconds the signature stays valid; it is only checked when the path is opened.
    /// - Returns: The path with its `authSig` query.
    public func signPath(_ path: String, expires: Int = 30) async throws -> String {
        try await requestString("auth/sign_path", data: ["path": path, "expires": expires], field: "path")
    }

    /// Error for a websocket command whose result lacks the expected field.
    public struct UnexpectedResponse: Error, Equatable {
        /// The command that answered unexpectedly.
        public let command: String
    }

    // MARK: - Private

    /// Sends a websocket command once (no retry across reconnects) and returns one string field of its result.
    private func requestString(_ command: String, data: [String: any Sendable], field: String) async throws -> String {
        let request = HARequest(type: .webSocket(command), data: data, shouldRetry: false)
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            connection.send(request) { result in
                switch result {
                case let .success(.dictionary(values)):
                    if let value = values[field] as? String {
                        continuation.resume(returning: value)
                    } else {
                        continuation.resume(throwing: UnexpectedResponse(command: command))
                    }
                case .success:
                    continuation.resume(throwing: UnexpectedResponse(command: command))
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Applies one HAKit delivery. HAKit's states cache always delivers the full set (thousands of entities)
    /// on every change, so converting and comparing all of them per event cost whole frames while scrolling.
    /// Only entities whose `last_updated` or state moved are converted (`HAEntity ==` compares those).
    func receive(_ entities: Set<HAEntity>) {
        let interval = Telemetry.begin(Telemetry.Name.entityUpdate)
        let delta = Self.delta(from: lastDelivered, to: entities)
        lastDelivered = delta.delivered
        if delta.isFirst {
            // The first live set replaces the disk snapshot, dropping entities the server no longer has.
            store.replaceAll(delta.changed, freshness: .live)
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
    static func delta(from previous: [String: HAEntity], to entities: Set<HAEntity>) -> Delta {
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

    private func refreshStatus() {
        let next: Status
        switch connection.state {
        case .connecting, .authenticating: next = .connecting
        case let .ready(version): next = .connected(version: version)
        case let .disconnected(reason):
            switch reason {
            case .disconnected: next = .disconnected
            case .rejected: next = .rejected
            case .waitingToReconnect: next = .waitingToReconnect
            }
        }
        if status != next { status = next }
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
