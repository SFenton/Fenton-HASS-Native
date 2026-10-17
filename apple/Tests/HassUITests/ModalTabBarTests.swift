@testable import HassUI
import HassCore
import SwiftUI
import Testing

/// The glass section bar (direction G): text and symbol segments, the accessibility-size menu, bottom by default.
@MainActor
struct ModalTabBarTests {
    private enum Section: String, CaseIterable, Identifiable {
        case controls, apps, settings
        var id: Self { self }
    }

    private func bar(symbols: Bool) -> some View {
        ModalTabBar(tabs: Section.allCases, label: "Remote sections", title: \.rawValue,
                    symbol: symbols ? { _ in "circle" } : nil, selection: .constant(.apps), identifier: "test.tabs")
            .frame(width: 360)
    }

    @Test func rendersTextAndSymbolSegmentsAndTheMenu() {
        #expect(ImageRenderer(content: bar(symbols: false)).cgImage != nil)
        #expect(ImageRenderer(content: bar(symbols: true)).cgImage != nil)
        #expect(ImageRenderer(content: bar(symbols: false).dynamicTypeSize(.accessibility5)).cgImage != nil)
    }

    @Test func pinsAlongTheBottomByDefault() {
        let page = Text("Content")
            .modalTabBar(Section.allCases, label: "Remote sections", title: \.rawValue,
                         selection: .constant(.controls), identifier: "test.tabs")
            .frame(width: 360, height: 400)
        #expect(ImageRenderer(content: page).cgImage != nil)
        #expect(ModalTabBarStyle.glassInset > 0)
    }

    @Test func iconsOnCompactWidthTextOtherwiseAndAMenuAtAccessibilitySizes() {
        typealias Style = ModalTabBarStyle
        #expect(Style.form(hasSymbols: true, compactWidth: true, accessibilitySize: false) == .icons, "iPhone shows the web's icons")
        #expect(Style.form(hasSymbols: true, compactWidth: false, accessibilitySize: false) == .text, "iPad shows titles")
        #expect(Style.form(hasSymbols: false, compactWidth: true, accessibilitySize: false) == .text, "No icons supplied")
        #expect(Style.form(hasSymbols: true, compactWidth: true, accessibilitySize: true) == .menu)
        #expect(Style.form(hasSymbols: false, compactWidth: false, accessibilitySize: true) == .menu)
    }

    @Test func everyModalSectionHasAnIconFromTheWeb() {
        for tab in MediaRemoteTab.allCases { #expect(ModalTabSymbols.symbol(for: tab) != "circle", "\(tab)") }
        for tab in HumidifierTab.allCases { #expect(ModalTabSymbols.symbol(for: tab) != "circle", "\(tab)") }
        for tab in BedSideSheet.Tab.allCases { #expect(ModalTabSymbols.symbol(for: tab) != "circle", "\(tab)") }
        for tab in WakeLightSheet.Tab.allCases { #expect(ModalTabSymbols.symbol(for: tab) != "circle", "\(tab)") }
        for tab in ClimateConfig.Tab.allCases { #expect(ModalTabSymbols.symbol(for: tab) != "circle", "\(tab)") }
        #expect(ModalTabSymbols.mdi(for: MediaRemoteTab.hueSync) == "mdi:lightbulb-multiple")
        #expect(ModalTabSymbols.mdi(for: ClimateConfig.Tab.rooms) == "mdi:home-thermometer")
        #expect(ModalTabSymbols.mdi(for: BedSideSheet.Tab.alarms) == "mdi:alarm")
    }
}
