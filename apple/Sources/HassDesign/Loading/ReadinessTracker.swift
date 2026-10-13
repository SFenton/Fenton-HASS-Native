import SwiftUI

/// Collects which pieces of content inside a ``ContentGate`` are still loading (pattern:
/// `.agents/patterns/content-gate.md`).
///
/// Content reports itself with ``SwiftUICore/View/contentReadiness(_:isReady:)``; ``CachedImage`` does so
/// automatically, so a gated page waits for the images on screen as well as its data.
@MainActor
@Observable
public final class ReadinessTracker {
    /// Ids of content that has reported and is not ready yet.
    public private(set) var pending: Set<String> = []

    /// Creates an empty tracker.
    public init() {}

    /// Whether every reported piece of content is ready.
    public var isSettled: Bool { pending.isEmpty }

    /// Records whether `id` is ready.
    public func set(_ id: String, ready: Bool) {
        if ready {
            if pending.contains(id) { pending.remove(id) }
        } else if !pending.contains(id) {
            pending.insert(id)
        }
    }
}

extension EnvironmentValues {
    /// The enclosing gate's tracker, if any.
    @Entry public var readinessTracker: ReadinessTracker? = nil
}

public extension View {
    /// Holds the enclosing ``ContentGate`` (if any) until `isReady`, so its spinner gives way only once this
    /// content can draw. Leaving the screen counts as ready.
    /// - Parameters:
    ///   - id: Unique within the gate, e.g. `image:<url>`.
    ///   - isReady: Whether this content has what it needs to draw.
    func contentReadiness(_ id: String, isReady: Bool) -> some View {
        modifier(ReadinessRequirement(id: id, isReady: isReady))
    }
}

private struct ReadinessRequirement: ViewModifier {
    var id: String
    var isReady: Bool
    @Environment(\.readinessTracker) private var tracker

    func body(content: Content) -> some View {
        content
            .onAppear { tracker?.set(id, ready: isReady) }
            .onChange(of: isReady) { _, ready in tracker?.set(id, ready: ready) }
            .onDisappear { tracker?.set(id, ready: true) }
    }
}
