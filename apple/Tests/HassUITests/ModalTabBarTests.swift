@testable import HassUI
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
}
