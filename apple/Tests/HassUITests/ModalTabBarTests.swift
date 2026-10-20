@testable import HassUI
import HassCore
import HassDesign
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

    // MARK: Badges

    @Test func aBarWithBadgesDrawsItsOwnSegmentsWhateverTheWidth() {
        typealias Style = ModalTabBarStyle
        #expect(Style.form(hasSymbols: true, hasBadges: true, compactWidth: true, accessibilitySize: false) == .badged, "iPhone: icons with badges")
        #expect(Style.form(hasSymbols: true, hasBadges: true, compactWidth: false, accessibilitySize: false) == .badgedWithTitles, "iPad: icon over title")
        #expect(Style.form(hasSymbols: false, hasBadges: true, compactWidth: true, accessibilitySize: false) == .badgedWithTitles, "No icons: titles")
        #expect(Style.form(hasSymbols: true, hasBadges: true, compactWidth: true, accessibilitySize: true) == .menu, "AX sizes: the menu")
        #expect(Style.form(hasSymbols: true, hasBadges: false, compactWidth: true, accessibilitySize: false) == .icons, "No badges: the system control")
    }

    @Test func badgesCapAtNinePlusAndAreSpokenAfterTheName() {
        #expect(ModalTabBarStyle.badgeText(0) == nil)
        #expect(ModalTabBarStyle.badgeText(3) == "3")
        #expect(ModalTabBarStyle.badgeText(9) == "9")
        #expect(ModalTabBarStyle.badgeText(10) == "9+")
        #expect(ModalTabBarStyle.accessibilityTitle("Overdue Chores", badge: 3) == "Overdue Chores, 3 items")
        #expect(ModalTabBarStyle.accessibilityTitle("Overdue Chores", badge: 1) == "Overdue Chores, 1 item")
        #expect(ModalTabBarStyle.accessibilityTitle("Overdue Chores", badge: 0) == "Overdue Chores")
    }

    @Test func segmentsAreAtLeast44PointsTall() {
        #expect(ModalTabBarStyle.iconSegmentHeight >= 44)
        #expect(ModalTabBarStyle.titledSegmentHeight >= 44)
    }

    private func badgedBar() -> some View {
        ModalTabBar(tabs: Section.allCases, label: "Remote sections", title: \.rawValue, symbol: { _ in "circle" },
                    badge: { $0 == .controls ? 12 : $0 == .apps ? 2 : 0 }, selection: .constant(.apps), identifier: "test.tabs")
            .frame(width: 360)
    }

    @Test func rendersBadgedSegmentsAndTheirMenu() {
        #expect(ImageRenderer(content: badgedBar()).cgImage != nil)
        #expect(ImageRenderer(content: badgedBar().environment(\.horizontalSizeClass, .regular)).cgImage != nil)
        #expect(ImageRenderer(content: badgedBar().dynamicTypeSize(.accessibility5)).cgImage != nil)
    }

    @Test func everyModalSectionHasAnIconFromTheWeb() {
        for tab in MediaRemoteTab.allCases { #expect(ModalTabSymbols.symbol(for: tab) != "circle", "\(tab)") }
        for tab in HumidifierTab.allCases { #expect(ModalTabSymbols.symbol(for: tab) != "circle", "\(tab)") }
        for tab in BedSideSheet.Tab.allCases { #expect(ModalTabSymbols.symbol(for: tab) != "circle", "\(tab)") }
        for tab in WakeLightSheet.Tab.allCases { #expect(ModalTabSymbols.symbol(for: tab) != "circle", "\(tab)") }
        for tab in ClimateConfig.Tab.allCases { #expect(ModalTabSymbols.symbol(for: tab) != "circle", "\(tab)") }
        for tab in SummaryTab.allCases { #expect(SymbolMap.symbol(for: tab.mdiIcon) != "circle", "\(tab)") }
        #expect(ModalTabSymbols.mdi(for: MediaRemoteTab.hueSync) == "mdi:lightbulb-multiple")
        #expect(ModalTabSymbols.mdi(for: ClimateConfig.Tab.rooms) == "mdi:home-thermometer")
        #expect(ModalTabSymbols.mdi(for: BedSideSheet.Tab.alarms) == "mdi:alarm")
    }
}
