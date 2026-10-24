#if os(macOS)
import AppKit
import HassCore
import HassDesign
@testable import HassUI
import SwiftUI
import Testing

/// VoiceOver-only semantics fixed from the HIG review (mockup atlas, bucket "VoiceOver & accessibility"): state as
/// traits and values, content in values rather than hints, one Button per tap target.
@MainActor
@Suite(.serialized, .enabled(if: AXWindow.isAvailable, "Needs accessibility permission for the test host"))
struct VoiceOverSemanticsTests {
    @Test func aSelectableOptionSpeaksItsDescriptionAsValueAndSelectionAsTrait() async throws {
        let rows = VStack {
            SelectableOptionRow(title: "Away", detail: "Nobody home.", symbol: "figure.walk", tint: .orange, isSelected: true) {}
                .accessibilityIdentifier("opt.away")
            SelectableOptionRow(title: "Guest", detail: "Visitors staying.", symbol: "person", tint: .orange, isSelected: false) {}
                .accessibilityIdentifier("opt.guest")
        }.frame(width: 360).padding()
        let driver = AXWindow(rows, size: CGSize(width: 400, height: 300))
        defer { driver.close() }
        await driver.window.settle(0.5)
        let nodes = await driver.nodes()
        let away = try #require(nodes.first { $0.identifier == "opt.away" })
        let guest = try #require(nodes.first { $0.identifier == "opt.guest" })
        #expect(away.value == "Nobody home." && guest.value == "Visitors staying.", "the description is content, not a hint")
        #expect(away.isSelected && !guest.isSelected)
        #expect(away.frame.height >= 44 && guest.frame.height >= 44)
    }

    @Test func aBedroomRowGivesItsSwitchItsOwnStopBesideTheOpenButton() async throws {
        var opened = 0
        let row = BedroomRow(symbol: "alarm", title: "7:00 AM", lines: ["Enabled"], onOpen: { opened += 1 }, openIdentifier: "row.open") {
            Toggle("7:00 AM", isOn: .constant(true)).labelsHidden().accessibilityIdentifier("row.switch")
        }.frame(width: 360).padding()
        let driver = AXWindow(row, size: CGSize(width: 400, height: 140))
        defer { driver.close() }
        await driver.window.settle(0.5)
        let nodes = await driver.nodes()
        let open = try #require(nodes.first { $0.identifier == "row.open" })
        let toggle = try #require(nodes.first { $0.identifier == "row.switch" })
        #expect(open.role == "AXButton", "the text is a Button, not a tap gesture")
        #expect(!open.frame.intersects(toggle.frame), "the switch is a sibling, not inside the button")
        #expect(open.frame.height >= 44)
        #expect(await driver.press(open))
        #expect(opened == 1)
    }
}
#endif
