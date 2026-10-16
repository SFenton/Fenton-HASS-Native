@testable import HassDesign
import SwiftUI
import Testing

@MainActor
struct FloatingActionBarTests {
    private func render(_ view: some View, width: CGFloat = 402) -> CGImage? {
        let renderer = ImageRenderer(content: view.frame(width: width))
        return renderer.cgImage
    }

    private func actions(active: Bool = false) -> [FloatingAction] {
        [
            FloatingAction(id: "filter", title: "Filter", symbol: "slider.horizontal.3", showsTitle: false, isActive: active) {},
            FloatingAction(id: "add", title: "Add Task", symbol: "plus") {},
            FloatingAction(id: "scan", title: "Scan Item", symbol: "barcode.viewfinder", isProminent: false) {},
        ]
    }

    @Test func rendersActionsSearchAndExpandedSearch() {
        #expect(render(FloatingActionBar(actions: actions())) != nil)
        #expect(render(FloatingActionBar(actions: actions(active: true))) != nil)
        let collapsed = FloatingSearch(text: .constant("milk"), isExpanded: .constant(false), prompt: "Search")
        #expect(render(FloatingActionBar(actions: actions(), search: collapsed)) != nil)
        let expanded = FloatingSearch(text: .constant(""), isExpanded: .constant(true), prompt: "Search")
        #expect(render(FloatingActionBar(actions: actions(), search: expanded)) != nil)
        #expect(render(FloatingActionBar(actions: actions()).dynamicTypeSize(.accessibility5)) != nil)
        #expect(render(FloatingActionBar(actions: actions(), search: collapsed).dynamicTypeSize(.accessibility5)) != nil)
    }

    @Test func modifierDrawsNothingWithoutActions() {
        #expect(render(Color.clear.frame(height: 200).floatingActionBar([])) != nil)
        #expect(render(Color.clear.frame(height: 200).floatingActionBar(actions())) != nil)
    }

    @Test func actionsKeepTheirValues() {
        var tapped = false
        let action = FloatingAction(id: "add", title: "Add", symbol: "plus") { tapped = true }
        #expect(action.showsTitle && !action.isActive && action.isProminent)
        action.action()
        #expect(tapped)
    }

    /// The prominent capsule's white label and an active circle's black glyph need 4.5:1 on their fills (WCAG 1.4.3):
    /// G's `#0071E3` and `#F2F2F7`.
    @Test func tintsKeepTextReadable() {
        func luminance(_ r: Double, _ g: Double, _ b: Double) -> Double {
            func channel(_ value: Double) -> Double {
                let c = value / 255
                return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
        }
        func contrastWithWhite(_ r: Double, _ g: Double, _ b: Double) -> Double { 1.05 / (luminance(r, g, b) + 0.05) }
        func contrastWithBlack(_ r: Double, _ g: Double, _ b: Double) -> Double { (luminance(r, g, b) + 0.05) / 0.05 }
        #expect(HassTokens.Palette.tintFill == 0x0071E3)
        #expect(contrastWithWhite(0x00, 0x71, 0xE3) >= 4.5)
        #expect(contrastWithBlack(0xF2, 0xF2, 0xF7) >= 4.5)
        #expect(FloatingActionBar.size >= HassTokens.minTarget)
    }

    @Test func filterSheetAndRowsRender() {
        let sheet = FilterSheet(title: "Sort", canApply: true, canReset: true, onApply: {}, onReset: {}) {
            FilterSection("Sort By") {
                FilterOptionRow(title: "Alphabetical", subtitle: "Sort titles from A to Z.", isSelected: true) {}
                FilterOptionRow(title: "Expiring Soon", isSelected: false) {}
            }
        }
        #expect(render(sheet.frame(height: 600)) != nil)
        #expect(render(FilterSection("Minimum Ingredients Available") { Text("Any") }.dynamicTypeSize(.accessibility5)) != nil)
        #expect(render(FilterOptionRow(title: "Alphabetical", isSelected: true) {}.dynamicTypeSize(.accessibility5)) != nil)
    }

    @Test func filterSheetDetentsDefaultUnlessGiven() {
        let standard = FilterSheet(title: "Sort", canApply: false, canReset: false, onApply: {}, onReset: {}) { EmptyView() }
        #expect(standard.detents == nil)
        let tall = FilterSheet(title: "Filter", canApply: false, canReset: false, onApply: {}, onReset: {}, detents: [.large]) { EmptyView() }
        #expect(tall.detents == [.large])
        #expect(render(tall.frame(height: 600)) != nil)
    }

    @Test func editToolbarRendersIdleBusyAndDisabled() {
        for (enabled, busy) in [(true, false), (false, false), (true, true)] {
            let sheet = NavigationStack {
                Text("Draft")
                    .toolbar {
                        SheetCancelItem(isEnabled: !busy) {}
                        SheetConfirmItem("Save", isEnabled: enabled, isBusy: busy, busyTitle: "Saving") {}
                    }
            }
            #expect(render(sheet.frame(height: 300)) != nil)
        }
    }
}
