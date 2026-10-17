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
/// Ends the test host, with a message, when a sweep stops advancing: a control that raises a system panel (a menu, a
/// picker, a permission prompt) holds the main thread in a modal loop, and nothing in the test can get it back.
final class SweepWatchdog: @unchecked Sendable {
    static let shared = SweepWatchdog()
    private let lock = NSLock()
    private var current = ""
    private var stamp = Date()
    private var armed = false
    private var started = false

    /// The main actor is still getting work done (a click, a read of the tree): a busy machine, not a modal loop.
    func touch() {
        lock.lock()
        stamp = Date()
        lock.unlock()
    }

    func mark(_ action: String, armed: Bool = true) {
        lock.lock()
        current = action
        stamp = Date()
        self.armed = armed
        let start = !started
        started = true
        lock.unlock()
        if start {
            Thread.detachNewThread { [self] in
                while true {
                    Thread.sleep(forTimeInterval: 5)
                    lock.lock()
                    let stuck = armed && Date().timeIntervalSince(stamp) > 240
                    let action = current
                    lock.unlock()
                    if stuck {
                        let message = "Test host stuck for 240 s after: \(action). A system panel probably took the main thread; add the control to ControlSweepTests.endsTheSweep.\n"
                        FileHandle.standardError.write(Data(message.utf8))
                        try? message.write(toFile: NSTemporaryDirectory() + "sweep-hang.txt", atomically: true, encoding: .utf8)
                        // Where the main thread is, for whoever finds the control that did it.
                        let sample = Process()
                        sample.executableURL = URL(fileURLWithPath: "/usr/bin/sample")
                        sample.arguments = ["\(ProcessInfo.processInfo.processIdentifier)", "2", "-file", NSTemporaryDirectory() + "sweep-hang-sample.txt"]
                        try? sample.run()
                        sample.waitUntilExit()
                        _exit(3)
                    }
                }
            }
        }
    }
}

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
        /// Whether the element carries the selected trait (a chosen day, a picked tab).
        let isSelected: Bool
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
    func nodes(limit: Int = 4000, sheetOnly: Bool = false, stopWhen: ((Node) -> Bool)? = nil) async -> [Node] {
        SweepWatchdog.shared.touch()
        let pid = ProcessInfo.processInfo.processIdentifier
        // The tree is briefly empty while the window relayouts; ask again.
        for _ in 0..<5 {
            let expected = Self.axFrame(of: hosted.window)
            // On the main thread: in this process an accessibility query runs on the calling thread, and AppKit builds
            // the table cells it reads there (off the main thread that trips its auto layout checks).
            let found = Self.walk(pid: pid, expected: expected, limit: limit, sheetOnly: sheetOnly, stopWhen: stopWhen)
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
        var waited: TimeInterval = 0
        while waited < timeout {
            if let found = await node(identifier) { return found }
            await hosted.settle(0.15)
            waited += 0.2
        }
        return await node(identifier)
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

    /// Runs the main run loop briefly (a plain function, so the async click may call it).
    private static func pump(_ seconds: TimeInterval) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

    /// The window, its sheets and the sheets and alerts on those, the topmost first.
    private func windowsFrontToBack() -> [NSWindow] {
        var windows: [NSWindow] = []
        func collect(_ window: NSWindow) {
            window.sheets.forEach(collect)
            windows.append(window)
        }
        collect(hosted.window)
        return windows
    }

    /// Makes every view class in the hierarchy accept the click that arrives while its window is not key (what a click
    /// does to an inactive window). Replaces `acceptsFirstMouse(for:)` on each class up the chain.
    private static func acceptFirstMouse(in view: NSView) {
        let selector = #selector(NSView.acceptsFirstMouse(for:))
        let accept: @convention(block) (AnyObject, NSEvent?) -> Bool = { _, _ in true }
        var current: AnyClass? = Swift.type(of: view)
        while let cls = current, cls != NSObject.self {
            if class_getInstanceMethod(cls, selector) != nil {
                class_replaceMethod(cls, selector, imp_implementationWithBlock(accept), "B@:@")
            }
            current = class_getSuperclass(cls)
        }
        view.subviews.forEach(acceptFirstMouse)
    }

    /// Clicks the centre of `frame` (screen coordinates, top-left origin, as accessibility reports them) with real
    /// mouse events sent to the window under that point, the sheet first. Returns whether a window took them.
    private func click(at frame: CGRect, along fraction: CGFloat = 0) async -> Bool {
        SweepWatchdog.shared.touch()
        guard !frame.isEmpty, let screen = NSScreen.screens.first else { return false }
        // Text and rows only hit where they draw (a click between two words misses): aim at the leading glyph, or
        // `fraction` of the way along the frame on a retry.
        let x = fraction == 0 ? frame.minX + min(12, frame.width / 2) : frame.minX + frame.width * fraction
        let screenPoint = CGPoint(x: x, y: screen.frame.maxY - frame.midY)
        guard let target = windowsFrontToBack().first(where: { $0.frame.contains(screenPoint) }) else { return false }
        let location = target.convertPoint(fromScreen: screenPoint)
        // The host is often not the active application (another one has the front, or the screen is locked), and an
        // inactive window swallows its first click unless its views accept first mouse: say they do.
        if let content = target.contentView { Self.acceptFirstMouse(in: content) }
        target.makeKeyAndOrderFront(nil)
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

    /// Scrolls the window's content (its sheet's, when one is up) until the element is in view and
    /// clear of the bars: a click outside the window reaches nothing. Returns the element at its new position.
    private func reveal(_ node: Node) async -> Node {
        var current = node
        let target = hosted.window.attachedSheet ?? hosted.window
        for _ in 0..<16 {
            let bounds = Self.axFrame(of: target)
            let y = current.frame.midY
            if y > bounds.minY + 80, y < bounds.maxY - 90 { return current }
            guard target.scrollContent(by: y > bounds.midY ? 250 : -250) else { break }
            await hosted.settle(0.15)
            if !current.identifier.isEmpty, let fresh = await self.node(current.identifier) { current = fresh }
        }
        return current
    }

    /// Drags across the element along its vertical centre, from `start` to `end` (0 is its leading edge, 1 its trailing
    /// edge), in `steps` moves: the gesture of a slider or a dimmer tile.
    @discardableResult
    func drag(_ node: Node?, from start: CGFloat, to end: CGFloat, steps: Int = 8) async -> Bool {
        guard let node, !node.frame.isEmpty, let screen = NSScreen.screens.first else { return false }
        func point(_ fraction: CGFloat) -> CGPoint {
            CGPoint(x: node.frame.minX + node.frame.width * fraction, y: screen.frame.maxY - node.frame.midY)
        }
        guard let target = windowsFrontToBack().first(where: { $0.frame.contains(point(start)) }) else { return false }
        if let content = target.contentView { Self.acceptFirstMouse(in: content) }
        func send(_ type: NSEvent.EventType, _ fraction: CGFloat) {
            let location = target.convertPoint(fromScreen: point(fraction))
            guard let event = NSEvent.mouseEvent(
                with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: target.windowNumber, context: nil, eventNumber: 0, clickCount: type == .mouseMoved ? 0 : 1,
                pressure: type == .leftMouseUp ? 0 : 1
            ) else { return }
            target.sendEvent(event)
        }
        target.makeKeyAndOrderFront(nil)
        send(.mouseMoved, start)
        await hosted.settle(0.05)
        send(.leftMouseDown, start)
        await hosted.settle(0.05)
        for step in 1...steps {
            send(.leftMouseDragged, start + (end - start) * CGFloat(step) / CGFloat(steps))
            await hosted.settle(0.05)
        }
        send(.leftMouseUp, end)
        await hosted.settle(0.25)
        return true
    }

    /// Presses the element, as a tap does. Returns whether the press was accepted.
    @discardableResult
    func press(_ node: Node?, along fraction: CGFloat = 0) async -> Bool {
        guard let found = node else { return false }
        let node = await reveal(found)
        let ok = await click(at: node.frame, along: fraction)
        await hosted.settle(0.15)
        return ok
    }

    /// Presses `identifier` until `condition` holds over the window's elements, at most `attempts` times: a synthesised
    /// click now and then lands between two glyphs of a label, or is lost while the machine is busy, and does nothing.
    func press(_ identifier: String, attempts: Int = 4, until condition: ([Node]) -> Bool) async -> Bool {
        for attempt in 0..<attempts {
            guard let node = await waitFor(identifier) else { return false }
            if await press(node, until: condition, attempts: 1, firstAt: [0, 0.5, 0.3, 0.7][attempt % 4]) { return true }
        }
        return false
    }

    /// Presses a found element until `condition` holds (an element with no identifier of its own, such as a tab).
    func press(_ node: Node, attempts: Int = 4, until condition: ([Node]) -> Bool) async -> Bool {
        await press(node, until: condition, attempts: attempts, firstAt: 0)
    }

    private func press(_ node: Node, until condition: ([Node]) -> Bool, attempts: Int, firstAt: CGFloat) async -> Bool {
        for attempt in 0..<attempts {
            let fraction = attempt == 0 ? firstAt : [0.5, 0.3, 0.7][attempt % 3]
            guard await press(node, along: fraction) else { return false }
            if condition(await wait(timeout: 8, condition)) { return true }
        }
        return false
    }

    /// Presses the element with `identifier`, waiting for it to appear.
    @discardableResult
    func press(_ identifier: String) async -> Bool {
        await press(await waitFor(identifier))
    }

    /// What pressing one control did to a gallery's last-call line.
    struct PressOutcome: CustomStringConvertible {
        var identifier: String
        /// The last-call line afterwards when the press changed it; nil when it sent nothing.
        var call: String?
        var description: String { "\(identifier) -> \(call ?? "nothing")" }
    }

    /// Presses, one after another, every enabled button, switch and radio button whose identifier starts with one of
    /// `prefixes` (in the sheet only, when `inSheet`), and records which of them changed the last-call line (a press that
    /// opens a page or a sheet sends nothing). A sheet a press opens is swept too, `descend` levels deep, then closed;
    /// an alert a press raises inside a sheet is closed so the sweep goes on.
    func pressEach(prefixes: [String], inSheet: Bool = false, descend: Int = 0, skipping: (String) -> Bool = { _ in false },
                   lastCall id: String = "gallery.lastCall") async -> [PressOutcome] {
        let roles: Set<String> = ["AXButton", "AXCheckBox", "AXRadioButton"]
        func pressable() async -> [String] {
            var seen = Set<String>()
            return await nodes(sheetOnly: inSheet).filter { node in
                !node.identifier.isEmpty && prefixes.contains { node.identifier.hasPrefix($0) } && roles.contains(node.role) && node.isEnabled
                    && !skipping(node.identifier)
            }.map(\.identifier).filter { seen.insert($0).inserted }
        }
        // A page or sheet can take a while to appear when the machine is busy.
        var identifiers = await pressable()
        var waited: TimeInterval = 0
        while identifiers.isEmpty, waited < 15 {
            await hosted.settle(0.3)
            waited += 0.4
            identifiers = await pressable()
        }
        // A launch that opens its sheet straight away (a device, a vacuum, a light) is swept as that sheet.
        if !inSheet, hosted.window.attachedSheet != nil {
            let swept = await pressEach(prefixes: prefixes, inSheet: true, descend: descend, skipping: skipping, lastCall: id)
            await closeSheet()
            return swept
        }
        var outcomes: [PressOutcome] = []
        var before = await text(id)
        defer { SweepWatchdog.shared.mark("sweep finished", armed: false) }
        for identifier in identifiers {
            SweepWatchdog.shared.mark("pressing \(identifier)")
            let sheetBefore = hosted.window.attachedSheet
            // A page-level press with a sheet still up would land on the sheet.
            if !inSheet, sheetBefore != nil { break }
            guard let node = await node(identifier), await press(node) else { continue }
            var after = await text(id)
            if after == before {
                // A call can land a pass later (it goes through a task).
                await hosted.settle(0.15)
                after = await text(id)
            }
            outcomes.append(PressOutcome(identifier: identifier, call: after != before ? after : nil))
            before = after
            if inSheet, let sheet = hosted.window.attachedSheet, let alert = sheet.attachedSheet {
                sheet.endSheet(alert)
                await hosted.settle(0.4)
            } else if !inSheet, let sheet = hosted.window.attachedSheet, sheet !== sheetBefore {
                if descend > 0 {
                    outcomes += await pressEach(prefixes: [""], inSheet: true, descend: descend - 1, skipping: skipping, lastCall: id)
                }
                await closeSheet()
            }
        }
        return outcomes
    }

    /// Closes the sheet the window has up the way a person does, by its close or cancel button (ending the sheet from
    /// outside leaves SwiftUI's presentation state set, so it comes back).
    func closeSheet() async {
        guard let open = hosted.window.attachedSheet else { return }
        if let alert = open.attachedSheet {
            open.endSheet(alert)
            await hosted.settle(0.3)
        }
        let buttons = await nodes(sheetOnly: true).filter { $0.role == "AXButton" && $0.isEnabled }
        let close = buttons.first { button in ["close", "cancel"].contains { button.identifier.lowercased().contains($0) } }
            ?? buttons.first { ["Close", "Cancel", "Done"].contains($0.spoken) }
        if let close { _ = await press(close) }
        for _ in 0..<15 where hosted.window.attachedSheet != nil { await hosted.settle(0.2) }
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

    /// Types into the field until `condition` holds, at most `attempts` times: under load the first value can land on
    /// a field that is rebuilt a moment later.
    @discardableResult
    func type(_ text: String, into identifier: String, attempts: Int = 3, until condition: ([Node]) -> Bool) async -> Bool {
        for _ in 0..<attempts {
            guard await type(text, into: await waitFor(identifier)) else { return false }
            if condition(await wait(timeout: 6, condition)) { return true }
        }
        return false
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
        kAXEnabledAttribute, kAXPositionAttribute, kAXSizeAttribute, kAXChildrenAttribute, kAXSelectedAttribute,
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

    private nonisolated static func walk(pid: pid_t, expected: CGRect, limit: Int, sheetOnly: Bool, stopWhen: ((Node) -> Bool)?) -> [Node] {
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
            if sheetOnly {
                // Start from the window's sheets, not the page behind them.
                queue = read(window).1.filter { read($0).0.role == "AXSheet" }
            }
            var next = 0
            while next < queue.count, result.count < limit {
                let (node, children) = read(queue[next])
                next += 1
                result.append(node)
                if stopWhen?(node) == true { return result }
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
        let selected = (array.count > 9 ? (array[9] as? NSNumber)?.boolValue : nil) ?? false
        let node = Node(
            element: element, role: string(0), identifier: string(1), title: string(2), label: string(3), value: string(4),
            isEnabled: enabled, isSelected: selected, frame: CGRect(origin: point(6), size: size(7))
        )
        return (node, children)
    }
}
#endif
