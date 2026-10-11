import HassDesign
import SwiftUI
import UIKit
import XCTest

/// SwiftUI builds its accessibility tree only while an assistive technology or UI automation is running.
/// Turn automation on for this test process, as accessibility snapshot tools do (`libAccessibility`).
@MainActor private let enableAccessibilityAutomation: Void = {
    guard let library = dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW),
          let symbol = dlsym(library, "_AXSSetAutomationEnabled") else { return }
    typealias SetEnabled = @convention(c) (Int32) -> Void
    unsafeBitCast(symbol, to: SetEnabled.self)(1)
}()

/// VoiceOver's adjustable action on the thermostat dial handles, through the real accessibility elements
/// SwiftUI exposes in the app (`.agents/patterns/thermostat-dial.md`). XCUITest can only adjust sliders,
/// so this hosts the dial in a window and calls `accessibilityIncrement()` / `accessibilityDecrement()`
/// as VoiceOver's swipe up and down do.
@MainActor
final class ThermostatDialAccessibilityTests: XCTestCase {
    private var window: UIWindow?

    override func tearDown() async throws {
        window?.isHidden = true
        window = nil
    }

    // MARK: - Helpers

    /// Hosts a dial in a key window and returns the commits it sends.
    private func host(_ configuration: ThermostatDialConfiguration, commits: @escaping (ThermostatTargets) -> Void) throws -> UIView {
        enableAccessibilityAutomation
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let controller = UIHostingController(rootView: ThermostatDial(configuration, size: .modal, onCommit: commits)
            .frame(width: 340, height: 340))
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 340, height: 340)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        self.window = window
        return controller.view
    }

    /// The accessibility element with `identifier`, searched through views and their accessibility children.
    private func element(_ identifier: String, in root: NSObject) -> NSObject? {
        var queue: [NSObject] = [root]
        var seen = Set<ObjectIdentifier>()
        while !queue.isEmpty {
            let object = queue.removeFirst()
            guard seen.insert(ObjectIdentifier(object)).inserted else { continue }
            if Self.identifier(of: object) == identifier { return object }
            if let view = object as? UIView { queue += view.subviews }
            if let children = object.accessibilityElements as? [NSObject] { queue += children }
            let count = object.accessibilityElementCount()
            if count != NSNotFound, count > 0 {
                queue += (0..<count).compactMap { object.accessibilityElement(at: $0) as? NSObject }
            }
        }
        return nil
    }

    /// SwiftUI's accessibility nodes answer `accessibilityIdentifier` without declaring
    /// `UIAccessibilityIdentification`, so ask by selector.
    private static func identifier(of object: NSObject) -> String? {
        let selector = #selector(getter: UIAccessibilityIdentification.accessibilityIdentifier)
        guard object.responds(to: selector) else { return nil }
        return object.perform(selector)?.takeUnretainedValue() as? String
    }

    /// Waits up to a second for SwiftUI to publish `identifier`.
    private func handle(_ identifier: String, in root: UIView) throws -> NSObject {
        let deadline = Date().addingTimeInterval(1)
        while Date() < deadline {
            if let found = element(identifier, in: root) { return found }
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        return try XCTUnwrap(element(identifier, in: root), "\(identifier) was not exposed")
    }

    // MARK: - Tests

    /// Swipe up on the cool-to handle raises it one step and commits the new range.
    func testIncrementRaisesTheCoolToHandleOneStep() throws {
        var commits: [ThermostatTargets] = []
        let root = try host(.init(title: "Whole Home", current: 71, targets: .range(low: 68, high: 75), action: "idle")) {
            commits.append($0)
        }
        let high = try handle("thermostatDial.handle.high", in: root)
        XCTAssertTrue(high.accessibilityTraits.contains(.adjustable))
        XCTAssertEqual(high.accessibilityLabel, "Whole Home cool to")
        XCTAssertEqual(high.accessibilityValue, "75 degrees")
        high.accessibilityIncrement()
        XCTAssertEqual(commits, [.range(low: 68, high: 75.5)])
    }

    /// Swipe down on a single target lowers it one step and commits.
    func testDecrementLowersTheTargetOneStep() throws {
        var commits: [ThermostatTargets] = []
        let root = try host(.init(title: "Living Room", current: 68.5, targets: .single(72), action: "heating")) {
            commits.append($0)
        }
        let target = try handle("thermostatDial.handle.target", in: root)
        XCTAssertTrue(target.accessibilityTraits.contains(.adjustable))
        target.accessibilityDecrement()
        XCTAssertEqual(commits, [.single(71.5)])
    }

    /// An unavailable dial exposes no handle to adjust.
    func testUnavailableDialHasNoHandles() throws {
        let root = try host(.init(title: "Garage", current: nil, targets: nil, action: "unavailable", isUnavailable: true)) { _ in
            XCTFail("An unavailable dial must not commit")
        }
        XCTAssertNotNil(try handle("thermostatDial.readout", in: root))
        XCTAssertNil(element("thermostatDial.handle.target", in: root))
    }
}
