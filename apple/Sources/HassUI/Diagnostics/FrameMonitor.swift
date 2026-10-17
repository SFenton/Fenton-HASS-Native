import HassTelemetry
import SwiftUI
#if os(iOS)
import QuartzCore
import UIKit
#endif

/// Measures frame pacing while a page scrolls (pattern: `.agents/patterns/telemetry.md`).
///
/// A display link runs only while some page is scrolling and telemetry records, so it costs nothing otherwise. Each
/// frame's duration is compared with the display's budget (8.3 ms at 120 Hz); frames past half a budget late count
/// as hitches and add to that page's ``ScrollStats`` in ``Telemetry/log``. Every scroll is also a `Scroll`
/// signpost interval and every hitch a `Hitch` event, for Instruments.
@MainActor
public final class FrameMonitor {
    /// The app's monitor.
    public static let shared = FrameMonitor()

    #if os(iOS)
    private var link: CADisplayLink?
    #endif
    private var active: [String: Telemetry.Interval] = [:]
    private var frames: [String: [Double]] = [:]
    private var lastTimestamp: CFTimeInterval?
    private var budgetMs = 1000.0 / 60
    private var census: ResourceCensus.Registration?

    init() {
        census = ResourceCensus.shared.register { [weak self] in ["FrameMonitor.displayLinks": self?.displayLinkCount ?? 0] }
    }

    /// Display links running now: one while a page scrolls with telemetry on, else none.
    var displayLinkCount: Int {
        #if os(iOS)
        link == nil ? 0 : 1
        #else
        0
        #endif
    }

    /// Whether any page is scrolling.
    public var isMonitoring: Bool { !active.isEmpty }

    /// Starts counting frames for `page`.
    public func beginScroll(page: String) {
        guard active[page] == nil else { return }
        active[page] = Telemetry.begin(Telemetry.Name.scroll, page: page, page)
        guard Telemetry.isEnabled else { return }
        startLink()
    }

    /// Stops counting frames for `page` and records its stats.
    public func endScroll(page: String) {
        guard let interval = active.removeValue(forKey: page) else { return }
        let pageFrames = frames.removeValue(forKey: page) ?? []
        Telemetry.log.addScroll(page: page, frameMs: pageFrames, budgetMs: budgetMs)
        let hitchMs = pageFrames.reduce(0) { $0 + max(0, $1 - budgetMs * 1.5 > 0 ? $1 - budgetMs : 0) }
        Telemetry.end(interval, value: hitchMs, detail: "\(pageFrames.count) frames")
        if active.isEmpty { stopLink() }
    }

    /// Adds one frame to every scrolling page (the display link calls it; tests call it directly).
    func record(frameMs: Double, budgetMs: Double) {
        self.budgetMs = budgetMs
        for page in active.keys {
            frames[page, default: []].append(frameMs)
            if frameMs - budgetMs > budgetMs / 2 {
                Telemetry.event(Telemetry.Name.hitch, page: page, value: frameMs - budgetMs)
            }
        }
    }

    // MARK: Display link

    #if os(iOS)
    private func startLink() {
        guard link == nil else { return }
        let link = CADisplayLink(target: DisplayLinkTarget(monitor: self), selector: #selector(DisplayLinkTarget.tick(_:)))
        // Ask for the panel's top rate so 120 Hz devices are measured against 120 Hz.
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
        lastTimestamp = nil
    }

    private func stopLink() {
        link?.invalidate()
        link = nil
        lastTimestamp = nil
    }

    fileprivate func tick(_ link: CADisplayLink) {
        defer { lastTimestamp = link.timestamp }
        guard let lastTimestamp else { return }
        let budget = max(link.targetTimestamp - link.timestamp, 1.0 / 120)
        record(frameMs: (link.timestamp - lastTimestamp) * 1000, budgetMs: budget * 1000)
    }
    #else
    private func startLink() {}
    private func stopLink() {}
    #endif
}

#if os(iOS)
/// Keeps the display link from retaining the monitor.
private final class DisplayLinkTarget: NSObject {
    weak var monitor: FrameMonitor?
    init(monitor: FrameMonitor) { self.monitor = monitor }

    @MainActor @objc func tick(_ link: CADisplayLink) { monitor?.tick(link) }
}
#endif

// MARK: - Modifier

public extension View {
    /// Records this scroll view's frame pacing under `page` (``FrameMonitor``). Apply to the page's main
    /// `ScrollView` or `List`. iOS 18 and later; earlier systems record nothing.
    func scrollTelemetry(_ page: String) -> some View {
        modifier(ScrollTelemetry(page: page))
    }
}

private struct ScrollTelemetry: ViewModifier {
    var page: String

    func body(content: Content) -> some View {
        if #available(iOS 18, macOS 15, *) {
            content
                .onScrollPhaseChange { _, phase in
                    if phase == .idle {
                        FrameMonitor.shared.endScroll(page: page)
                    } else {
                        FrameMonitor.shared.beginScroll(page: page)
                    }
                }
                .onDisappear { FrameMonitor.shared.endScroll(page: page) }
        } else {
            content
        }
    }
}
