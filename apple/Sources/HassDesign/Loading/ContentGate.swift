import HassTelemetry
import SwiftUI

// MARK: - Readiness tracking

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

// MARK: - Gate model

/// The phases of a ``ContentGate``, ported from the web's recipe results region
/// (`ha-sfenton-react-dash@f5a7bf9:src/components/hass/recipes/useRecipeCollection.ts:47-49`).
@MainActor
@Observable
public final class ContentGateModel {
    /// Where the gate is.
    public enum Phase: Equatable, Sendable {
        /// Content is hidden; the spinner shows once ``Timing/spinnerDelay`` passes.
        case loading
        /// Content went from ready back to loading and is fading out.
        case exiting
        /// Everything is ready and the spinner is fading out.
        case spinnerExiting
        /// Content is fading (and rising) in.
        case entering
        /// Content shows; nothing is animating.
        case idle

        /// Content draws (possibly fading).
        public var showsContent: Bool { self == .entering || self == .idle || self == .exiting }
    }

    /// Transition timings. Web values except the spinner delay, which keeps fast loads from flashing a spinner.
    public enum Timing {
        /// Before the spinner fades in.
        public static let spinnerDelay: Duration = .milliseconds(150)
        /// Spinner fade in.
        public static let spinnerEnter: Duration = .milliseconds(200)
        /// Spinner fade out (web `CRITERIA_SPINNER_EXIT_MS`).
        public static let spinnerExit: Duration = .milliseconds(140)
        /// Content fade in (web `CRITERIA_CONTENT_ENTER_MS`).
        public static let contentEnter: Duration = .milliseconds(170)
        /// Content fade out when reloading (web `CRITERIA_CONTENT_EXIT_MS`).
        public static let contentExit: Duration = .milliseconds(170)
        /// The longest the gate waits for reported content (images) after the data is ready.
        public static let childTimeout: Duration = .milliseconds(1500)
    }

    /// The current phase.
    public private(set) var phase: Phase
    /// Whether the spinner is visible (it fades in after ``Timing/spinnerDelay``).
    public private(set) var spinnerShown = false
    /// Content inside the gate reports here.
    public let tracker = ReadinessTracker()

    /// The page name for telemetry.
    @ObservationIgnored public let page: String
    @ObservationIgnored private let sleep: @MainActor (Duration) async -> Bool
    @ObservationIgnored private var interval: Telemetry.Interval?

    /// Creates a model.
    /// - Parameters:
    ///   - page: Names the page in telemetry.
    ///   - isReady: Whether data is already there. A gate that starts ready never shows a spinner or fades
    ///     (a reopen from the disk snapshot must not look like a reload).
    ///   - sleep: Waits; returns `false` when cancelled. Tests pass an immediate one.
    public init(page: String, isReady: Bool, sleep: @escaping @MainActor (Duration) async -> Bool = ContentGateModel.taskSleep) {
        self.page = page
        self.sleep = sleep
        phase = isReady ? .idle : .loading
        if !isReady { interval = Telemetry.begin(Telemetry.Name.contentReady, page: page, page) }
        if isReady { Telemetry.count("gate.instant") }
    }

    /// The production sleeper.
    public static func taskSleep(_ duration: Duration) async -> Bool {
        do {
            try await Task.sleep(for: duration)
            return true
        } catch {
            return false
        }
    }

    /// Moves the gate toward `isReady`. The view calls it whenever the data or the reported content changes;
    /// a newer call cancels an older one mid-transition and picks up from the current phase.
    public func advance(isReady: Bool, reduceMotion: Bool = false) async {
        if !isReady {
            await becomeLoading()
            return
        }
        switch phase {
        case .idle:
            return
        case .loading, .exiting:
            if !tracker.isSettled {
                // The tracker settling cancels this wait and calls again.
                guard await sleep(Timing.childTimeout) else { return }
                Telemetry.count("gate.childTimeouts")
            }
            if spinnerShown {
                withAnimation(.easeOut(duration: Timing.spinnerExit.seconds)) { phase = .spinnerExiting }
                guard await sleep(Timing.spinnerExit) else { return }
            }
            await enter(reduceMotion: reduceMotion)
        case .spinnerExiting:
            await enter(reduceMotion: reduceMotion)
        case .entering:
            finish()
        }
    }

    private func becomeLoading() async {
        if phase.showsContent {
            withAnimation(.easeOut(duration: Timing.contentExit.seconds)) { phase = .exiting }
            guard await sleep(Timing.contentExit) else { return }
        }
        if phase != .loading {
            phase = .loading
            spinnerShown = false
            interval = Telemetry.begin(Telemetry.Name.contentReady, page: page, page)
        }
        guard !spinnerShown, await sleep(Timing.spinnerDelay) else { return }
        withAnimation(.easeIn(duration: Timing.spinnerEnter.seconds)) { spinnerShown = true }
    }

    private func enter(reduceMotion: Bool) async {
        withAnimation(.easeOut(duration: Timing.contentEnter.seconds)) {
            phase = .entering
            spinnerShown = false
        }
        guard await sleep(Timing.contentEnter) else { return }
        finish()
    }

    private func finish() {
        phase = .idle
        if let interval {
            Telemetry.end(interval, detail: "cold")
            self.interval = nil
        }
    }
}

extension Duration {
    /// The duration in seconds, for SwiftUI animations.
    var seconds: Double { milliseconds / 1000 }
}

// MARK: - Gate view

/// Waits for a page's content before showing it, the way the web app does (pattern:
/// `.agents/patterns/content-gate.md`).
///
/// While loading, the content is laid out but hidden and a centered spinner fades in (after a short delay, so a
/// fast load shows no spinner at all). Once `isReady` is true **and** every piece of content that reported itself
/// (images through ``CachedImage``, anything using ``SwiftUICore/View/contentReadiness(_:isReady:)``) is ready, or
/// ``ContentGateModel/Timing/childTimeout`` passes, the spinner fades out and the content fades in. A gate created
/// with `isReady` already true (data from the disk snapshot or a cache) shows content immediately with no
/// animation.
///
/// HIG: [Loading](https://developer.apple.com/design/human-interface-guidelines/loading) (show content as soon as
/// possible; an indeterminate indicator for unknown waits) and
/// [Motion](https://developer.apple.com/design/human-interface-guidelines/motion) (Reduce Motion drops the rise and
/// keeps the fade).
public struct ContentGate<Content: View>: View {
    private var isReady: Bool
    private var content: Content
    @State private var model: ContentGateModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Creates a gate.
    /// - Parameters:
    ///   - page: Names the page in telemetry (`ContentReady` signposts).
    ///   - isReady: Whether the page's data is loaded.
    ///   - content: The page content.
    public init(page: String, isReady: Bool, @ViewBuilder content: () -> Content) {
        self.isReady = isReady
        self.content = content()
        _model = State(initialValue: ContentGateModel(page: page, isReady: isReady))
    }

    private struct Input: Equatable {
        var isReady: Bool
        var settled: Bool
    }

    public var body: some View {
        let phase = model.phase
        ZStack {
            content
                .environment(\.readinessTracker, model.tracker)
                .opacity(phase == .entering || phase == .idle ? 1 : 0)
                .modifier(RiseIn(active: phase != .idle && phase != .entering && !reduceMotion))
                .allowsHitTesting(phase.showsContent)
                .accessibilityHidden(!phase.showsContent)
            if !phase.showsContent {
                ProgressView()
                    .controlSize(.large)
                    .opacity(model.spinnerShown && phase == .loading ? 1 : 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Loading")
                    .accessibilityIdentifier("contentGate.spinner")
            }
        }
        .task(id: Input(isReady: isReady, settled: model.tracker.isSettled)) {
            await model.advance(isReady: isReady, reduceMotion: reduceMotion)
        }
    }
}

/// Holds content 4 pt low while hidden so it rises into place as it fades in (web `recipeResultsEnter`).
private struct RiseIn: ViewModifier {
    var active: Bool

    func body(content: Content) -> some View {
        content.offset(y: active ? 4 : 0)
    }
}
