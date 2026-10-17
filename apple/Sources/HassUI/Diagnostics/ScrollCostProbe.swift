import HassTelemetry
import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Scrolls the front scroll view by itself for a fixed time and reports what that cost (pattern:
/// `.agents/patterns/telemetry.md`, "Scroll cost"; tests: `ScrollSurfacesPerformanceTests`).
///
/// With `FENTON_SCROLLCOST=1` the root view carries an invisible element, `diagnostics.scrollcost`, and listens for two
/// Darwin notifications a test posts once the surface under test is on screen:
/// - `com.sfenton.home.scrollcost.scroll`: drags the page up and down at a steady speed;
/// - `com.sfenton.home.scrollcost.idle`: waits the same time without moving.
///
/// When the time is up the element's label becomes ``MainThreadCostMeter/Report/summary``. The scroll is driven by a
/// display link setting the content offset each frame, so none of the cost is an XCUITest swipe or the accessibility
/// snapshot it asks for, and the same code runs in a Release build on a phone. The idle run is the floor to subtract.
struct ScrollCostProbe: View {
    /// Whether this launch carries the probe.
    static let isEnabled = ProcessInfo.processInfo.environment["FENTON_SCROLLCOST"] == "1"

    /// The dashboard path a scroll cost launch opens first (`FENTON_SCROLLCOST_OPEN=climate`, `living-room`, `settings`),
    /// so a run needs no taps; nil outside a scroll cost launch.
    static let launchPath: String? = isEnabled ? ProcessInfo.processInfo.environment["FENTON_SCROLLCOST_OPEN"] : nil

    static let scrollNotification = "com.sfenton.home.scrollcost.scroll"
    static let idleNotification = "com.sfenton.home.scrollcost.idle"

    @State private var label = "ready"
    @State private var driver = ScrollCostDriver()

    var body: some View {
        Color.clear
            .frame(width: 2, height: 2)
            .allowsHitTesting(false)
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityIdentifier("diagnostics.scrollcost")
            #if os(iOS)
            .task { await listen() }
            .task { await autorun() }
            #endif
    }

    #if os(iOS)
    /// Waits for the test's notifications and runs one measurement per notification.
    private func listen() async {
        for await name in Self.notifications() {
            label = "running"
            let report = await driver.run(scrolling: name == Self.scrollNotification)
            label = report.map(\.summary) ?? "no scroll view: " + ScrollCostDriver.describeScrollViews()
        }
    }

    /// With `FENTON_SCROLLCOST_AUTORUN=<seconds>`: after that many seconds on screen, measures idle, scroll and scroll
    /// again by itself and appends one `SCROLLCOST<TAB>name<TAB>kind<TAB>summary` line per run to
    /// `FENTON_SCROLLCOST_FILE` (`FENTON_SCROLLCOST_NAME` names the surface) and prints it. No test drives the app, so no accessibility
    /// client is attached either, and the same launch works on a phone (`xcrun devicectl device process launch`).
    private func autorun() async {
        let environment = ProcessInfo.processInfo.environment
        guard let delay = environment["FENTON_SCROLLCOST_AUTORUN"].flatMap(Double.init) else { return }
        let path = environment["FENTON_SCROLLCOST_FILE"]
        let name = environment["FENTON_SCROLLCOST_NAME"] ?? "surface"
        try? await Task.sleep(for: .seconds(delay))
        for kind in ["idle", "scroll", "scroll"] {
            let report = await driver.run(scrolling: kind == "scroll")
            let line = report.map(\.summary) ?? "no scroll view: " + ScrollCostDriver.describeScrollViews()
            label = line
            Self.append("SCROLLCOST\t\(name)\t\(kind)\t\(line)\n", to: path)
            if report == nil { break }
        }
        Self.append("SCROLLCOST_DONE\t\(name)\n", to: path)
        // `devicectl --console` waits for the app to end, so a phone launch asks it to.
        if environment["FENTON_SCROLLCOST_EXIT"] == "1" { exit(0) }
    }

    /// Prints the line (a phone launched with `devicectl --console` returns it) and appends it to `path` when there is one.
    private static func append(_ text: String, to path: String?) {
        print(text, terminator: "")
        fflush(stdout)
        guard let path, let data = text.data(using: .utf8) else { return }
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            FileManager.default.createFile(atPath: path, contents: data)
        }
    }

    /// The two Darwin notifications as an async stream of their names.
    private static func notifications() -> AsyncStream<String> {
        AsyncStream { continuation in
            let center = CFNotificationCenterGetDarwinNotifyCenter()
            let observer = Unmanaged.passRetained(NotificationSink { continuation.yield($0) })
            for name in [scrollNotification, idleNotification] {
                CFNotificationCenterAddObserver(center, observer.toOpaque(), { _, observer, name, _, _ in
                    guard let observer, let name else { return }
                    Unmanaged<NotificationSink>.fromOpaque(observer).takeUnretainedValue().handler(name.rawValue as String)
                }, name as CFString, nil, .deliverImmediately)
            }
            continuation.onTermination = { _ in
                CFNotificationCenterRemoveEveryObserver(center, observer.toOpaque())
                observer.release()
            }
        }
    }

    private final class NotificationSink: @unchecked Sendable {
        let handler: @Sendable (String) -> Void
        init(_ handler: @escaping @Sendable (String) -> Void) { self.handler = handler }
    }
    #endif
}

#if os(iOS)
/// Finds the front scroll view and moves it.
@MainActor
final class ScrollCostDriver {
    private var link: CADisplayLink?
    private var target: DisplayLinkTarget?

    /// Seconds a run lasts and the scroll speed in points per second (`FENTON_SCROLLCOST_SECONDS`, `_SPEED`).
    private var seconds: Double { Double(ProcessInfo.processInfo.environment["FENTON_SCROLLCOST_SECONDS"] ?? "") ?? 10 }
    /// `FENTON_SCROLLCOST_AXIS=horizontal` drives the widest sideways scroll view (a carousel or rail) instead of the page.
    private var horizontal: Bool { ProcessInfo.processInfo.environment["FENTON_SCROLLCOST_AXIS"] == "horizontal" }
    private var speed: Double { Double(ProcessInfo.processInfo.environment["FENTON_SCROLLCOST_SPEED"] ?? "") ?? 900 }

    /// Runs one measurement.
    /// - Parameter scrolling: Drag the front scroll view, or wait without touching anything.
    /// - Returns: The cost, or nil when scrolling was asked for and no scroll view is on screen.
    func run(scrolling: Bool) async -> MainThreadCostMeter.Report? {
        var scrollView: UIScrollView?
        if scrolling {
            scrollView = Self.frontScrollView(horizontal: horizontal)
            guard scrollView != nil else { return nil }
        }
        let meter = MainThreadCostMeter()
        let counters = Telemetry.log.counters
        let startedAt = Date.now
        let end = ContinuousClock.now + .seconds(seconds)
        // Let the notification's own turn settle before counting.
        try? await Task.sleep(for: .milliseconds(300))
        meter.begin()
        var distance = 0.0
        if let scrollView {
            let mover = Mover(scrollView: scrollView, speed: speed, horizontal: horizontal)
            start(mover)
            try? await Task.sleep(until: end, clock: .continuous)
            stop()
            distance = mover.travelled
        } else {
            try? await Task.sleep(until: end, clock: .continuous)
        }
        var report = meter.finish()
        report.travelledPoints = distance
        // Live updates the connection applied meanwhile, and what applying them cost on the main thread.
        let after = Telemetry.log.counters
        let updates = Telemetry.log.records.filter { $0.kind == "\(Telemetry.Name.entityUpdate)" && $0.date >= startedAt }
        report.note = "deliveries=\((after["entity.deliveries"] ?? 0) - (counters["entity.deliveries"] ?? 0))"
            + " changed=\((after["entity.changed"] ?? 0) - (counters["entity.changed"] ?? 0))"
            + " update_ms=\(String(format: "%.1f", updates.compactMap(\.durationMs).reduce(0, +)))"
        return report
    }

    private func start(_ mover: Mover) {
        let target = DisplayLinkTarget(mover: mover)
        let link = CADisplayLink(target: target, selector: #selector(DisplayLinkTarget.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.target = target
        self.link = link
    }

    private func stop() {
        link?.invalidate()
        link = nil
        target = nil
    }

    /// The visible vertical scroll view that covers the most of the front-most presented screen.
    static func frontScrollView(horizontal: Bool = false) -> UIScrollView? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first,
              let window = scene.keyWindow ?? scene.windows.first else { return nil }
        var controller = window.rootViewController
        while let presented = controller?.presentedViewController { controller = presented }
        let root: UIView = controller?.view ?? window
        var best: (view: UIScrollView, area: CGFloat)?
        var stack: [UIView] = [root]
        while let view = stack.popLast() {
            stack.append(contentsOf: view.subviews)
            guard let scroll = view as? UIScrollView, !scroll.isHidden, scroll.alpha > 0.01, scroll.window != nil else { continue }
            let visible = scroll.convert(scroll.bounds, to: window).intersection(window.bounds)
            if horizontal {
                // A carousel or rail: wider content than the view, and not the page.
                guard visible.width > 200, visible.height > 20,
                      scroll.contentSize.width > scroll.bounds.width + 1, scroll.contentSize.height <= scroll.bounds.height + 1
                else { continue }
            } else {
                guard visible.width > 200, visible.height > 200 else { continue }
                // A vertical scroller: the content is taller than the view, or wider content is not what scrolls it.
                guard scroll.contentSize.height > scroll.bounds.height + 1 else { continue }
            }
            let area = visible.width * visible.height
            if best == nil || area > best!.area { best = (scroll, area) }
        }
        return best?.view
    }

    /// Every scroll view in the key window with the facts ``frontScrollView()`` judges, for a run that finds none.
    static func describeScrollViews() -> String {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let window = scenes.compactMap({ $0.keyWindow ?? $0.windows.first }).first else { return "no window (\(scenes.count) scenes)" }
        var found: [String] = []
        var stack: [UIView] = [window]
        while let view = stack.popLast() {
            stack.append(contentsOf: view.subviews)
            guard let scroll = view as? UIScrollView else { continue }
            let frame = scroll.convert(scroll.bounds, to: window)
            found.append("\(type(of: scroll)) \(Int(frame.width))x\(Int(frame.height)) content=\(Int(scroll.contentSize.height)) alpha=\(scroll.alpha) hidden=\(scroll.isHidden)")
        }
        let presented = window.rootViewController?.presentedViewController.map { "\(type(of: $0))" } ?? "none"
        return "presented=\(presented) " + found.joined(separator: "; ")
    }

    /// Moves a scroll view up and down at a steady speed, one step per frame.
    @MainActor
    final class Mover {
        let scrollView: UIScrollView
        let speed: Double
        private(set) var travelled = 0.0
        private var direction = 1.0
        private var last: CFTimeInterval?

        let horizontal: Bool

        init(scrollView: UIScrollView, speed: Double, horizontal: Bool = false) {
            self.scrollView = scrollView
            self.speed = speed
            self.horizontal = horizontal
        }

        func step(_ link: CADisplayLink) {
            defer { last = link.timestamp }
            guard let last else { return }
            let delta = min(link.timestamp - last, 0.1) * speed
            let inset = scrollView.adjustedContentInset
            if horizontal {
                let start = -inset.left
                let end = max(start, scrollView.contentSize.width - scrollView.bounds.width + inset.right)
                var x = scrollView.contentOffset.x + direction * delta
                if x >= end { x = end; direction = -1 } else if x <= start { x = start; direction = 1 }
                travelled += delta
                scrollView.setContentOffset(CGPoint(x: x, y: scrollView.contentOffset.y), animated: false)
                return
            }
            let top = -inset.top
            let bottom = max(top, scrollView.contentSize.height - scrollView.bounds.height + inset.bottom)
            var y = scrollView.contentOffset.y + direction * delta
            if y >= bottom { y = bottom; direction = -1 } else if y <= top { y = top; direction = 1 }
            travelled += delta
            scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: y), animated: false)
        }
    }

    private final class DisplayLinkTarget: NSObject {
        let mover: Mover
        init(mover: Mover) { self.mover = mover }
        @MainActor @objc func tick(_ link: CADisplayLink) { mover.step(link) }
    }
}
#else
/// macOS (hosted tests) has no scroll views to drive.
@MainActor
final class ScrollCostDriver {
    func run(scrolling: Bool) async -> MainThreadCostMeter.Report? { nil }
}
#endif
