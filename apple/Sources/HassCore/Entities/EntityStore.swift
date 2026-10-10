import Foundation
import Observation

/// Observable holder for one entity, so a view that reads it redraws only when that entity changes.
@MainActor
@Observable
public final class EntityBox: Identifiable {
    /// The entity id this box tracks; stable for the box's life.
    public let id: String
    /// The latest state, or `nil` if the server doesn't know this entity.
    public internal(set) var state: EntityState?

    init(id: String, state: EntityState?) {
        self.id = id
        self.state = state
    }
}

/// The app's single source of entity state.
///
/// Updates are applied in place: a box is created once per entity id and only mutated when its value
/// actually changes, so reconnects and snapshot restores never make views reload.
@MainActor
@Observable
public final class EntityStore {
    /// Where the current values came from.
    public enum Freshness: Equatable, Sendable {
        /// Nothing loaded yet.
        case empty
        /// Restored from disk; live data not yet received.
        case snapshot(savedAt: Date)
        /// Receiving live updates.
        case live
    }

    /// Where the current values came from.
    public private(set) var freshness: Freshness = .empty

    @ObservationIgnored private var boxes: [String: EntityBox] = [:]
    @ObservationIgnored private var values: [String: EntityState] = [:]

    /// Number of times a box value was replaced. Tests use it to prove unchanged entities are not republished.
    @ObservationIgnored public private(set) var publishedChangeCount = 0

    /// Creates an empty store.
    public init() {}

    // MARK: - Reading

    /// The observable box for an entity. Always returns the same box for the same id.
    public func entity(_ entityId: String) -> EntityBox {
        if let box = boxes[entityId] { return box }
        let box = EntityBox(id: entityId, state: values[entityId])
        boxes[entityId] = box
        return box
    }

    /// The current value without observation, for non-UI code.
    public func value(_ entityId: String) -> EntityState? { values[entityId] }

    /// All current values.
    public var allValues: [String: EntityState] { values }

    // MARK: - Writing

    /// Replaces the whole state with a full set (initial load or reconnect), diffing in place.
    /// - Parameters:
    ///   - states: Every entity the server reports.
    ///   - freshness: The resulting freshness.
    public func replaceAll(_ states: [EntityState], freshness: Freshness = .live) {
        var incoming: [String: EntityState] = [:]
        incoming.reserveCapacity(states.count)
        for state in states { incoming[state.entityId] = state }
        for removed in values.keys where incoming[removed] == nil {
            values[removed] = nil
            publish(removed, nil)
        }
        for (id, state) in incoming where values[id] != state {
            values[id] = state
            publish(id, state)
        }
        if self.freshness != freshness { self.freshness = freshness }
    }

    /// Applies individual changes (a state_changed event or a compressed diff).
    public func apply(_ changes: [EntityState]) {
        for state in changes where values[state.entityId] != state {
            values[state.entityId] = state
            publish(state.entityId, state)
        }
    }

    /// Clears everything (sign out).
    public func reset() {
        for id in values.keys { publish(id, nil) }
        values = [:]
        freshness = .empty
    }

    private func publish(_ id: String, _ state: EntityState?) {
        guard let box = boxes[id] else { return }
        box.state = state
        publishedChangeCount += 1
    }
}
