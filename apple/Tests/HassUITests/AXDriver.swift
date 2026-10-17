#if os(macOS)
import AppKit
import ApplicationServices
import Foundation
import SwiftUI

/// Drives a hosted window the way an assistive client does, through the macOS accessibility API: finds a control by
/// its accessibility identifier or label, presses it, types into a field and reads values back.
///
/// SwiftUI builds no accessibility tree until a client asks, and the test host is a command-line tool that
/// accessibility refuses to talk to until it is a regular application (``enable()``). In this process an accessibility
/// query runs on the calling thread, so reads happen on the main actor; accessibility actions (`AXPress`,
/// `AXScrollToVisible`) end the host process, so a press is a real mouse event sent to the window instead, and text is
/// typed by setting a field's value. The process must be trusted for accessibility (``isAvailable``); tests that need
/// it skip when it is not, so the coverage gate on a machine without that permission reads low rather than passing
/// without them (`.agents/testing/apple/README.md`, Driving hosted windows).
@MainActor
final class AXWindow {
    /// Whether a test can drive windows on this machine.
    nonisolated static var isAvailable: Bool { AXIsProcessTrusted() }

    private static var enabled = false

    /// Makes the test host a regular application, once, so its windows answer accessibility queries.
    static func enable() {
        guard !enabled else { return }
        enabled = true
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.finishLaunching()
    }

    /// One accessibility element, read once.
    struct Node: @unchecked Sendable {
        let element: AXUIElement
        let role: String
        let identifier: String
        let title: String
        let label: String
        let value: String
        let isEnabled: Bool
        let frame: CGRect

        /// The text a screen reader would speak for the element: its label, else its title.
        var spoken: String { label.isEmpty ? title : label }
    }

    private let hosted: HostedWindow

    private static var slot = 0

    /// Hosts `view` in a window of `size`. Each window gets its own position, which is how its elements are told
    /// apart from those of other tests' windows (SwiftUI renames a window after its navigation title).
    init(_ view: some View, size: CGSize) {
        Self.enable()
        hosted = HostedWindow(view, size: size)
        Self.slot += 1
        hosted.window.setFrameOrigin(CGPoint(x: 20 + CGFloat(Self.slot % 150) * 5, y: 40 + CGFloat(Self.slot % 100) * 4))
    }

    var window: HostedWindow { hosted }

    func close() { hosted.close() }

    // MARK: Reading

    /// Every element in this window (and its sheets), depth first, up to `limit` elements.
    func nodes(limit: Int = 4000) async -> [Node] {
        let pid = ProcessInfo.processInfo.processIdentifier
        // The tree is briefly empty while the window relayouts; ask again.
        for _ in 0..<5 {
            let expected = Self.axFrame(of: hosted.window)
            // On the main thread: in this process an accessibility query runs on the calling thread, and AppKit builds
            // the table cells it reads there (off the main thread that trips its auto layout checks).
            let found = Self.walk(pid: pid, expected: expected, limit: limit)
            if !found.isEmpty { return found }
            await hosted.settle(0.1)
        }
        return []
    }

    /// The first element whose accessibility identifier is `identifier`.
    func node(_ identifier: String) async -> Node? {
        await nodes().first { $0.identifier == identifier }
    }

    /// The first element whose label or title is exactly `text`, optionally of `role` (for example `AXButton`).
    func node(label text: String, role: String? = nil) async -> Node? {
        await nodes().first { ($0.spoken == text || $0.title == text) && (role == nil || $0.role == role) }
    }

    /// Whether any element's label, title or value contains `text`.
    func shows(_ text: String) async -> Bool {
        await nodes().contains { $0.spoken.contains(text) || $0.value.contains(text) || $0.title.contains(text) }
    }

    /// Polls (in settle passes, not seconds) until `condition` holds over the window's elements.
    @discardableResult
    func wait(timeout: TimeInterval = 20, _ condition: ([Node]) -> Bool) async -> [Node] {
        var waited: TimeInterval = 0
        var current = await nodes()
        while !condition(current), waited < timeout {
            await hosted.settle(0.15)
            waited += 0.2
            current = await nodes()
        }
        return current
    }

    /// Waits for an element with `identifier` to exist and returns it.
    func waitFor(_ identifier: String, timeout: TimeInterval = 20) async -> Node? {
        await wait(timeout: timeout) { $0.contains { $0.identifier == identifier } }.first { $0.identifier == identifier }
    }

    /// The value (or label) of the element with `identifier`, as a screen reader would read it.
    func text(_ identifier: String) async -> String? {
        guard let found = await node(identifier) else { return nil }
        return found.value.isEmpty ? found.spoken : found.value
    }

    /// A one-line-per-element listing, for a failing test's message.
    func outline() async -> String {
        await nodes().map { "\($0.role) id=\($0.identifier) label=\($0.spoken) value=\($0.value) frame=\($0.frame)" }.joined(separator: "\n")
    }

    /// The values (or labels) of every element with `identifier`, in tree order.
    func texts(_ identifier: String) async -> [String] {
        await nodes().filter { $0.identifier == identifier }.map { $0.value.isEmpty ? $0.spoken : $0.value }
    }

    /// Waits for the last element with `identifier` to read something that satisfies `matches`, and returns that text
    /// (or the last text seen, so a failing expectation shows it).
    func text(_ identifier: String, timeout: TimeInterval = 20, where matches: (String) -> Bool) async -> String? {
        var last: String?
        await wait(timeout: timeout) { nodes in
            guard let found = nodes.last(where: { $0.identifier == identifier }) else { return false }
            last = found.value.isEmpty ? found.spoken : found.value
            return matches(last ?? "")
        }
        return last
    }

    // MARK: Acting

    /// Clicks the centre of `frame` (screen coordinates, top-left origin, as accessibility reports them) with real
    /// mouse events sent to the window under that point, the sheet first. Returns whether a window took them.
    private func click(at frame: CGRect, along fraction: CGFloat = 0) async -> Bool {
        guard !frame.isEmpty, let screen = NSScreen.screens.first else { return false }
        // Text and rows only hit where they draw (a click between two words misses): aim at the leading glyph, or
        // `fraction` of the way along the frame on a retry.
        let x = fraction == 0 ? frame.minX + min(12, frame.width / 2) : frame.minX + frame.width * fraction
        let screenPoint = CGPoint(x: x, y: screen.frame.maxY - frame.midY)
        let candidates = (hosted.window.sheets + [hosted.window]).filter { $0.frame.contains(screenPoint) }
        guard let target = candidates.first else { return false }
        let location = target.convertPoint(fromScreen: screenPoint)
        target.makeKey()
        func event(_ type: NSEvent.EventType) -> NSEvent? {
            NSEvent.mouseEvent(
                with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: target.windowNumber, context: nil, eventNumber: 0, clickCount: type == .mouseMoved ? 0 : 1,
                pressure: type == .leftMouseDown ? 1 : 0
            )
        }
        // Without a suspension between them: another test's window taking the key place between the press and the
        // release would drop the click.
        for type in [NSEvent.EventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
            guard let next = event(type) else { return false }
            target.sendEvent(next)
        }
        await hosted.settle(0.05)
        return true
    }

    /// Scrolls the window's content (its sheet's, when one is up) by wheel events until the element is in view and
    /// clear of the bars: a click outside the window reaches nothing. Returns the element at its new position.
    private func reveal(_ node: Node) async -> Node {
        var current = node
        let target = hosted.window.attachedSheet ?? hosted.window
        let screenTop = NSScreen.screens.first?.frame.maxY ?? 0
        for _ in 0..<16 {
            let bounds = Self.axFrame(of: target)
            let y = current.frame.midY
            if y > bounds.minY + 80, y < bounds.maxY - 90 { return current }
            let pixels: Int32 = y > bounds.midY ? -300 : 300
            guard let wheel = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: pixels, wheel2: 0, wheel3: 0) else { break }
            wheel.location = CGPoint(x: target.frame.midX, y: screenTop - target.frame.midY)
            wheel.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(target.windowNumber))
            wheel.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(target.windowNumber))
            if let event = NSEvent(cgEvent: wheel) { target.sendEvent(event) }
            await hosted.settle(0.15)
            if !current.identifier.isEmpty, let fresh = await self.node(current.identifier) { current = fresh }
        }
        return current
    }

    /// Presses the element, as a tap does. Returns whether the press was accepted.
    @discardableResult
    func press(_ node: Node?, along fraction: CGFloat = 0) async -> Bool {
        guard let found = node else { return false }
        let node = await reveal(found)
        let ok = await click(at: node.frame, along: fraction)
        await hosted.settle(0.25)
        return ok
    }

    /// Presses `identifier` until `condition` holds over the window's elements, at most `attempts` times: a synthesised
    /// click now and then lands between two glyphs of a label and does nothing.
    func press(_ identifier: String, attempts: Int = 3, until condition: ([Node]) -> Bool) async -> Bool {
        for attempt in 0..<attempts {
            guard await press(await waitFor(identifier), along: [0, 0.5, 0.3, 0.7][attempt % 4]) else { return false }
            let nodes = await wait(timeout: 6, condition)
            if condition(nodes) { return true }
        }
        return false
    }

    /// Presses the element with `identifier`, waiting for it to appear.
    @discardableResult
    func press(_ identifier: String) async -> Bool {
        await press(await waitFor(identifier))
    }

    /// Replaces the text of a field.
    @discardableResult
    func type(_ text: String, into node: Node?) async -> Bool {
        guard let node else { return false }
        let ok = AXUIElementSetAttributeValue(node.element, kAXValueAttribute as CFString, text as CFString) == .success
        await hosted.settle(0.25)
        return ok
    }

    /// Types into the field with `identifier`.
    @discardableResult
    func type(_ text: String, into identifier: String) async -> Bool {
        await type(text, into: await waitFor(identifier))
    }

    /// Performs a named action (`AXIncrement`, `AXDecrement`, `AXShowMenu`) on an element.
    @discardableResult
    func perform(_ action: String, on node: Node?) async -> Bool {
        guard let node else { return false }
        let ok = AXUIElementPerformAction(node.element, action as CFString) == .success
        await hosted.settle(0.25)
        return ok
    }

    // MARK: Tree walk

    private nonisolated static let attributes = [
        kAXRoleAttribute, kAXIdentifierAttribute, kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute,
        kAXEnabledAttribute, kAXPositionAttribute, kAXSizeAttribute, kAXChildrenAttribute,
    ] as [String]

    /// A window's frame as accessibility reports it: screen coordinates with the origin at the top left.
    private static func axFrame(of window: NSWindow) -> CGRect {
        let height = NSScreen.screens.first?.frame.maxY ?? 0
        return CGRect(x: window.frame.minX, y: height - window.frame.maxY, width: window.frame.width, height: window.frame.height)
    }

    private nonisolated static func frame(of element: AXUIElement) -> CGRect {
        var position = CGPoint.zero, size = CGSize.zero
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &value) == .success, let value {
            AXValueGetValue(value as! AXValue, .cgPoint, &position)
        }
        if AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &value) == .success, let value {
            AXValueGetValue(value as! AXValue, .cgSize, &size)
        }
        return CGRect(origin: position, size: size)
    }

    private nonisolated static func walk(pid: pid_t, expected: CGRect, limit: Int) -> [Node] {
        let app = AXUIElementCreateApplication(pid)
        var windows: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windows) == .success,
              let list = windows as? [AXUIElement] else { return [] }
        var result: [Node] = []
        for window in list {
            var name: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &name)
            _ = name
            guard Self.frame(of: window).integral == expected.integral else { continue }
            var queue = [window]
            while !queue.isEmpty, result.count < limit {
                let element = queue.removeFirst()
                let (node, children) = read(element)
                result.append(node)
                queue.append(contentsOf: children)
            }
        }
        return result
    }

    private nonisolated static func read(_ element: AXUIElement) -> (Node, [AXUIElement]) {
        var values: CFArray?
        let names = attributes as CFArray
        AXUIElementCopyMultipleAttributeValues(element, names, AXCopyMultipleAttributeOptions(rawValue: 0), &values)
        let array = (values as? [Any]) ?? []
        func string(_ index: Int) -> String {
            guard index < array.count else { return "" }
            if let text = array[index] as? String { return text }
            if let number = array[index] as? NSNumber { return number.stringValue }
            return ""
        }
        func point(_ index: Int) -> CGPoint {
            var p = CGPoint.zero
            if index < array.count, CFGetTypeID(array[index] as CFTypeRef) == AXValueGetTypeID() {
                AXValueGetValue(array[index] as! AXValue, .cgPoint, &p)
            }
            return p
        }
        func size(_ index: Int) -> CGSize {
            var s = CGSize.zero
            if index < array.count, CFGetTypeID(array[index] as CFTypeRef) == AXValueGetTypeID() {
                AXValueGetValue(array[index] as! AXValue, .cgSize, &s)
            }
            return s
        }
        let enabled = (array.count > 5 ? (array[5] as? NSNumber)?.boolValue : nil) ?? true
        let children = (array.count > 8 ? array[8] as? [AXUIElement] : nil) ?? []
        let node = Node(
            element: element, role: string(0), identifier: string(1), title: string(2), label: string(3), value: string(4),
            isEnabled: enabled, frame: CGRect(origin: point(6), size: size(7))
        )
        return (node, children)
    }
}
#endif
