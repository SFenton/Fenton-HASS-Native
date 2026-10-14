@testable import HassDesign
import SwiftUI
import Testing

@MainActor
struct PrimaryButtonTests {
    @Test func tintWithWhiteOrAFamilyWithDarkText() {
        let tint = PrimaryButtonStyle.colors(nil)
        #expect(tint.fill == HassTokens.Ink.actionFill)
        #expect(tint.label == .white)
        let water = PrimaryButtonStyle.colors(.water)
        #expect(water.fill == ColorFamily.water.glyph)
        #expect(water.label == Color(rgb: HassTokens.Palette.sheetGround))
        #expect(PrimaryButtonStyle.height == 50)
    }

    @Test func rendersEnabledDisabledAndAtAX5() {
        let buttons: [AnyView] = [
            AnyView(PrimaryButton("Add Missing Ingredients to Groceries", systemImage: "cart") {}),
            AnyView(PrimaryButton("Start Watering", family: .water) {}),
            AnyView(PrimaryButton("Save") {}.disabled(true)),
            AnyView(PrimaryButton("Save") {}.dynamicTypeSize(.accessibility5)),
        ]
        for button in buttons {
            #expect(ImageRenderer(content: button.frame(width: 340)).cgImage != nil)
        }
    }
}
