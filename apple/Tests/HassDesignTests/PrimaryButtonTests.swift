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
        // Fixed: the family's dark-appearance glyph, never the light-sheet variant.
        #expect(water.fill == Color(rgb: ColorFamily.water.spec.glyph))
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
