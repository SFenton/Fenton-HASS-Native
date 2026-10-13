import HassTelemetry
import SwiftUI

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
