#if os(macOS)
import AppKit
import Foundation
import HassCore
import HassDesign
@testable import HassUI
import SwiftUI
import Testing

// MARK: - Launch configuration

/// Sets launch environment variables (the `FENTON_GALLERY_*` switches the journeys use) and the launch
/// arguments the galleries read from `UserDefaults` (`-directionGSheet open`), runs `body`, and restores both.
///
/// Galleries read these when they are created or first drawn, so a test keeps them set while the window
/// settles. Suites that use it are serialized.
@MainActor
func withLaunch<T>(
    environment: [String: String] = [:], defaults: [String: String] = [:], _ body: () async throws -> T
) async rethrows -> T {
    let previousEnvironment = environment.keys.map { ($0, ProcessInfo.processInfo.environment[$0]) }
    let previousDefaults = defaults.keys.map { ($0, UserDefaults.standard.object(forKey: $0)) }
    for (key, value) in environment { setenv(key, value, 1) }
    for (key, value) in defaults { UserDefaults.standard.set(value, forKey: key) }
    defer {
        for (key, value) in previousEnvironment {
            if let value { setenv(key, value, 1) } else { unsetenv(key) }
        }
        for (key, value) in previousDefaults {
            if let value { UserDefaults.standard.set(value, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
        }
    }
    return try await body()
}

extension HostedWindow {
    /// What the window currently draws, as pixels: the sheet when one is attached (it draws in its own window).
    func snapshot() -> NSBitmapImageRep? {
        let target = window.attachedSheet ?? window
        guard let view = target.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }
}

extension HostedWindow {
    /// Scrolls the window's content (its sheet's, when one is up) from top to bottom with wheel events, so the rows a lazy
    /// list builds only when they come into view are drawn and their code runs.
    func scrollThrough(steps: Int = 6, pixels: Int32 = -450) async {
        let target = window.attachedSheet ?? window
        let screenTop = NSScreen.screens.first?.frame.maxY ?? 0
        for _ in 0..<steps {
            guard let wheel = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: pixels, wheel2: 0, wheel3: 0) else { return }
            wheel.location = CGPoint(x: target.frame.midX, y: screenTop - target.frame.midY)
            wheel.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(target.windowNumber))
            wheel.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(target.windowNumber))
            if let event = NSEvent(cgEvent: wheel) { target.sendEvent(event) }
            await settle(0.1)
        }
    }
}

extension NSBitmapImageRep {
    /// How many different colours a coarse grid of pixels holds: a blank or single-fill window reads one or two.
    var distinctColors: Int {
        var seen = Set<UInt32>()
        let step = max(1, min(pixelsWide, pixelsHigh) / 40)
        for y in stride(from: 0, to: pixelsHigh, by: step) {
            for x in stride(from: 0, to: pixelsWide, by: step) {
                guard let color = colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let r = UInt32(color.redComponent * 31), g = UInt32(color.greenComponent * 31), b = UInt32(color.blueComponent * 31)
                seen.insert(r << 10 | g << 5 | b)
            }
        }
        return seen.count
    }

    /// Whether `other` draws something different (a coarse, tolerant pixel comparison).
    func differs(from other: NSBitmapImageRep) -> Bool {
        guard pixelsWide == other.pixelsWide, pixelsHigh == other.pixelsHigh else { return true }
        let step = max(1, min(pixelsWide, pixelsHigh) / 60)
        for y in stride(from: 0, to: pixelsHigh, by: step) {
            for x in stride(from: 0, to: pixelsWide, by: step) {
                guard let a = colorAt(x: x, y: y)?.usingColorSpace(.sRGB), let b = other.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                if abs(a.redComponent - b.redComponent) + abs(a.greenComponent - b.greenComponent) + abs(a.blueComponent - b.blueComponent) > 0.08 {
                    return true
                }
            }
        }
        return false
    }
}

// MARK: - Gallery pages

/// Hosts each gallery page the journeys launch (`FENTON_GALLERY=<page>`) in a real window on a phone and a tablet,
/// with the launch switches the journeys pass, and checks the page draws content and that a switch changes it.
@MainActor
@Suite(.serialized)
struct GalleryLaunchTests {
    static let phone = CGSize(width: 402, height: 874)
    static let tablet = CGSize(width: 1210, height: 834)

    /// Hosts `page` and returns what it drew once it settled.
    func draw(_ page: ComponentGallery.Page, size: CGSize = GalleryLaunchTests.phone, settle: TimeInterval = 0.5) async -> NSBitmapImageRep? {
        let hosted = HostedWindow(ComponentGallery(page: page), size: size)
        defer { hosted.close() }
        await hosted.settle(settle)
        await hosted.scrollThrough(steps: 4)
        return hosted.snapshot()
    }

    @Test(arguments: ComponentGallery.Page.allCases)
    func everyGalleryPageDrawsOnAPhoneAndATablet(page: ComponentGallery.Page) async throws {
        for size in [Self.phone, Self.tablet] {
            let image = try #require(await draw(page, size: size), "\(page) at \(size)")
            #expect(image.distinctColors > 3, "\(page) drew a blank window at \(size)")
        }
    }

    @Test func directionGOrdersItsSectionsAndOpensItsSheetFromLaunchArguments() async throws {
        let closed = try #require(await draw(.directionG))
        let lower = try await withLaunch(defaults: ["directionGOrder": "lower"]) { try #require(await draw(.directionG)) }
        #expect(lower.differs(from: closed), "-directionGOrder lower puts the modules first")
        var sheets: [NSBitmapImageRep] = []
        for section in ["Controls", "Families", "Apps", "Settings"] {
            let sheet = try await withLaunch(defaults: ["directionGSheet": "open", "directionGSheetSection": section]) {
                try #require(await draw(.directionG, settle: 1.2))
            }
            #expect(sheet.distinctColors > 3, "\(section)")
            sheets.append(sheet)
        }
        #expect(sheets[0].differs(from: sheets[1]) && sheets[1].differs(from: sheets[3]), "each section draws its own content")
        let animated = try await withLaunch(defaults: ["directionGAnimate": "1"]) { try #require(await draw(.directionG)) }
        #expect(animated.distinctColors > 3)
    }

    @Test func performanceGalleryShowsTheScreenTheGateAndTheGrid() async throws {
        let screen = try #require(await draw(.performance))
        var others: [NSBitmapImageRep] = []
        for mode in ["gate", "grid"] {
            others.append(try await withLaunch(environment: ["FENTON_GALLERY_PERF": mode]) { try #require(await draw(.performance, settle: 1.2)) })
        }
        #expect(others.allSatisfy { $0.differs(from: screen) })
        #expect(others[0].differs(from: others[1]))
    }
}
#endif
