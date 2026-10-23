import HassTelemetry
import SwiftUI

public extension EnvironmentValues {
    /// Whether the page the view is on is being scrolled; a ticker holds still meanwhile (`.agents/design/motion.md` §9.10).
    /// Set by ``SwiftUICore/View/pausesTickersWhileScrolling()``.
    @Entry var pageIsScrolling = false
    /// Whether the view's section is on screen; a ticker holds still behind another tab. True outside the shell.
    @Entry var tickerIsOnScreen = true
}

public extension View {
    /// Tells the tickers inside this scroll view when it is moving, so they pause (iOS 18 and later; on iOS 17 they keep going).
    func pausesTickersWhileScrolling() -> some View { modifier(PausesTickersWhileScrolling()) }
}

private struct PausesTickersWhileScrolling: ViewModifier {
    @State private var scrolling = false

    func body(content: Content) -> some View {
        if #available(iOS 18, macOS 15, *) {
            content
                .onScrollPhaseChange { _, phase in scrolling = phase != .idle }
                .environment(\.pageIsScrolling, scrolling)
        } else {
            content
        }
    }
}

/// One line of text that scrolls like a ticker when it is wider than the room it has (pattern: `.agents/patterns/ticker.md`).
///
/// The label takes the width it is offered. If its natural width is wider, it plays ``MotionTokens/Ticker/passes`` passes of
/// ``TickerPlan`` (hold, travel at 30 pt/s, hold, return) after it appears or its text changes, with a soft fade at each edge,
/// then rests at the start. It runs only while it overflows, the scene is active, the view is on screen and its page is not
/// scrolling, and not at all under Reduce Motion (then ``wrapsWhenStill`` decides whether the text wraps or is cut). The ticker
/// text is hidden from accessibility: the caller names the content some other way.
public struct TickerLabel: View {
    var text: String
    var font: Font
    /// Wrap onto as many lines as the text needs instead of ticking (accessibility sizes, Reduce Motion).
    var wraps: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.pageIsScrolling) private var pageIsScrolling
    @Environment(\.tickerIsOnScreen) private var isOnScreen
    @State private var plan = TickerPlan(textWidth: 0, columnWidth: 0)
    @State private var onScreen = false
    @State private var clock = TickerClock()
    @State private var interval: Telemetry.Interval?
    @State private var lineHeight: CGFloat = 0
    @State private var height: CGFloat = 0
    /// Names the invisible element UI tests read the ticker's state from (see ``TickerLabel/probeEnabled``); nil adds none.
    var probe: String?

    /// - Parameters:
    ///   - text: The label.
    ///   - font: The label's font.
    ///   - wraps: Show the whole text on as many lines as it needs, and never tick.
    ///   - probe: An accessibility identifier for an invisible element that reports the ticker's state to UI tests
    ///     (`overflow`, `running`, `finished`, `wraps`, `lines`); added only when `FENTON_TICKER_PROBE=1` is in the environment.
    public init(_ text: String, font: Font = .headline, wraps: Bool = false, probe: String? = nil) {
        self.text = text
        self.font = font
        self.wraps = wraps
        self.probe = probe
    }

    /// Whether this launch adds the probe elements (UI tests set `FENTON_TICKER_PROBE=1`).
    static let probeEnabled = ProcessInfo.processInfo.environment["FENTON_TICKER_PROBE"] == "1"

    /// Whether the label may run now.
    var shouldRun: Bool {
        !wraps && !reduceMotion && plan.overflows && onScreen && isOnScreen && scenePhase == .active && !pageIsScrolling
            && !plan.isFinished(at: clock.elapsed(at: .now))
    }

    public var body: some View {
        Group {
            if wraps || reduceMotion {
                Text(text)
                    .font(font)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityHidden(true)
            } else {
                ticking
            }
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height = $0 }
        .background { if Self.probeEnabled, probe != nil { lineMeasure } }
        .overlay(alignment: .topLeading) { if Self.probeEnabled, let probe { probeElement(probe) } }
    }

    /// A hidden single line in the same font, to count lines by height.
    private var lineMeasure: some View {
        Text("Ag").font(font).lineLimit(1).hidden()
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { lineHeight = $0 }
            .accessibilityHidden(true)
    }

    private func probeElement(_ identifier: String) -> some View {
        let lines = lineHeight > 0 ? Int((height / lineHeight).rounded()) : 0
        let report = "overflow=\(plan.overflows ? 1 : 0) running=\(clock.isRunning ? 1 : 0) "
            + "finished=\(plan.isFinished(at: clock.elapsed(at: .now)) ? 1 : 0) wraps=\(wraps || reduceMotion ? 1 : 0) lines=\(lines)"
        return Color.clear
            .frame(width: 2, height: 2)
            .allowsHitTesting(false)
            .accessibilityElement()
            .accessibilityLabel(report)
            .accessibilityIdentifier(identifier)
    }

    /// The line's own height and the room it has come from this hidden copy, which truncates; the visible copy is an overlay
    /// that never changes the layout.
    private var ticking: some View {
        Text(text)
            .font(font)
            .lineLimit(1)
            .opacity(0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { plan.columnWidth = $0 }
            .overlay(alignment: .leading) { moving }
            .clipped()
            .onAppear { onScreen = true }
            .onDisappear { onScreen = false; pause(cause: "disappear") }
            .onChange(of: text) { pause(cause: "restart"); clock.restart(); sync() }
            .onChange(of: plan) { sync() }
            .onChange(of: onScreen) { sync() }
            .onChange(of: isOnScreen) { sync() }
            .onChange(of: scenePhase) { sync() }
            .onChange(of: pageIsScrolling) { sync() }
            .task(id: RunKey(running: shouldRun, text: text, plan: plan)) { await finishWhenDone() }
            .accessibilityHidden(true)
    }

    private var moving: some View {
        TimelineView(.animation(paused: !shouldRun)) { timeline in
            let elapsed = clock.elapsed(at: timeline.date)
            let offset = plan.offset(at: elapsed)
            Text(text)
                .font(font)
                .lineLimit(1)
                .fixedSize()
                .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { plan.textWidth = $0 }
                .offset(x: -offset)
                .frame(width: plan.columnWidth > 0 ? plan.columnWidth : nil, alignment: .leading)
                .mask(fade(offset: offset))
        }
    }

    /// A mask that is clear in the middle and fades each edge over ``MotionTokens/Ticker/fadeWidth``, the leading edge only once
    /// the text has moved (at rest the first letter stays solid, aligned with the glyph above), the trailing edge only while
    /// there is more text to the right.
    private func fade(offset: CGFloat) -> some View {
        let width = max(plan.columnWidth, 1)
        let fadeWidth = MotionTokens.Ticker.fadeWidth
        let leading = plan.overflows ? min(fadeWidth, offset) : 0
        let trailing = plan.overflows ? min(fadeWidth, max(plan.travel - offset, 0)) : 0
        let start = leading / width
        let end = 1 - trailing / width
        return LinearGradient(
            stops: [.init(color: .black.opacity(leading > 0 ? 0 : 1), location: 0), .init(color: .black, location: max(start, 0)),
                    .init(color: .black, location: min(end, 1)), .init(color: .black.opacity(trailing > 0 ? 0 : 1), location: 1)],
            startPoint: .leading, endPoint: .trailing
        )
    }

    // MARK: - Running

    private struct RunKey: Equatable {
        var running: Bool
        var text: String
        var plan: TickerPlan
    }

    /// Starts or pauses the clock to match ``shouldRun``.
    private func sync() {
        if plan.overflows, clock.isRunning == false, shouldRun {
            clock.resume(at: .now)
            interval = Telemetry.begin(Telemetry.Name.tickerRun, page: "Ticker", "run")
        } else if !shouldRun, clock.isRunning {
            pause(cause: plan.isFinished(at: clock.elapsed(at: .now)) ? "finished" : "paused")
        }
    }

    private func pause(cause: String) {
        guard clock.isRunning else { return }
        clock.pause(at: .now)
        if let interval { Telemetry.end(interval, detail: cause) }
        interval = nil
    }

    /// Sleeps until the last pass ends, then stops the clock so the timeline pauses and the label rests at the start.
    private func finishWhenDone() async {
        guard shouldRun || clock.isRunning else { return }
        let remaining = plan.totalDuration - clock.elapsed(at: .now)
        guard remaining > 0, shouldRun else { return }
        try? await Task.sleep(for: .seconds(remaining + 0.05))
        guard !Task.isCancelled else { return }
        sync()
    }
}

/// Seconds a ticker has played, kept across pauses.
struct TickerClock: Equatable {
    private var before: TimeInterval = 0
    private var resumedAt: Date?

    var isRunning: Bool { resumedAt != nil }

    func elapsed(at date: Date) -> TimeInterval {
        before + (resumedAt.map { max(0, date.timeIntervalSince($0)) } ?? 0)
    }

    mutating func resume(at date: Date) { if resumedAt == nil { resumedAt = date } }

    mutating func pause(at date: Date) {
        before = elapsed(at: date)
        resumedAt = nil
    }

    /// Back to the start (the text changed).
    mutating func restart() {
        before = 0
        resumedAt = nil
    }
}
