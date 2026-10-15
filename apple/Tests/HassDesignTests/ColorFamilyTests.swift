import Foundation
@testable import HassDesign
import SwiftUI
import Testing

struct ColorFamilyTests {
    /// WCAG relative luminance of `0xRRGGBB`.
    private func luminance(_ rgb: UInt32) -> Double {
        func linear(_ shift: UInt32) -> Double {
            let c = Double((rgb >> shift) & 0xFF) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(16) + 0.7152 * linear(8) + 0.0722 * linear(0)
    }

    private func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    @Test(arguments: ColorFamily.allCases)
    func inkOnFillPassesBodyContrast(_ family: ColorFamily) {
        guard let fill = family.spec.fill else { return }
        let ink: UInt32 = family.spec.darkInk ? 0x1C1C1E : 0xFFFFFF
        // Supporting text is white at 92% (or dark olive at 82%) over the fill.
        let secondary = family.spec.darkInk
            ? ColorFamily.mix(0x282000, fill, 0.82)
            : ColorFamily.mix(0xFFFFFF, fill, 0.92)
        #expect(contrast(ink, fill) >= 4.5, "\(family) title")
        #expect(contrast(secondary, fill) >= 4.5, "\(family) subtitle")
    }

    @Test(arguments: ColorFamily.allCases)
    func inkStillPassesOnTheProgressBand(_ family: ColorFamily) {
        guard let fill = family.spec.fill else { return }
        if family.spec.darkInk {
            let band = ColorFamily.mix(0xFFFFFF, fill, TileFaceStyle.progressLighten)
            #expect(contrast(0x1C1C1E, band) >= 4.5, "\(family) title on the band")
        } else {
            let shaded = ColorFamily.mix(0x000000, fill, TileFaceStyle.progressShade)
            #expect(contrast(ColorFamily.mix(0xFFFFFF, shaded, 0.92), shaded) >= 4.5, "\(family) state past the band")
            // The band itself is the plain fill, which inkOnFillPassesBodyContrast covers.
        }
    }

    @Test(arguments: ColorFamily.allCases)
    func glyphIsVisibleOnASheetTile(_ family: ColorFamily) {
        // Non-text contrast (WCAG 1.4.11) against the sheet's tile colour, #2C2C2E.
        #expect(contrast(family.spec.glyph, 0x2C2C2E) >= 3, "\(family)")
    }

    @Test(arguments: [0x0000FF, 0xFF0000, 0x00FF00, 0x8000FF, 0xFF00FF] as [UInt32])
    func litTileStatusReadsUnderAnyBulbColour(_ bulb: UInt32) {
        // The band's darker end, tinted by a saturated bulb, under the status text ("41%").
        let band = ColorFamily.mix(bulb, 0xFFE2B2, LitTile.bulbTint)
        let status = ColorFamily.mix(0x1C1C1E, band, LitTile.secondaryInkOpacity)
        #expect(contrast(status, band) >= 4.5, "bulb \(String(bulb, radix: 16))")
    }

    @Test func onlyLightsAndNeutralAreNeverFilled() {
        let unfilled = ColorFamily.allCases.filter { $0.spec.fill == nil }
        #expect(Set(unfilled) == [.lights, .neutral])
    }

    @Test(arguments: ColorFamily.allCases)
    func chipTextAndGlyphReadOnTheChipFill(_ family: ColorFamily) {
        guard let fill = family.chipFillRGB else { return }
        // Power's chip would need dark ink; no status chip uses it.
        guard family != .power else { return }
        // Text can sit under the chip's 12% white top highlight (`StatusChipStyle`), so measure against that too.
        let lifted = ColorFamily.mix(0xFFFFFF, fill, 0.12)
        for ground in [fill, lifted] {
            #expect(contrast(0xFFFFFF, ground) >= 4.5, "\(family) title and state")
        }
        #expect(contrast(family.chipGlyphRGB, fill) >= 3, "\(family) glyph")
    }

    @Test func alarmStatesPickTheirSecurityFamily() {
        #expect(ColorFamily.security(alarmState: "armed_home") == .securityHome)
        #expect(ColorFamily.security(alarmState: "armed_away") == .securityAway)
        #expect(ColorFamily.security(alarmState: "armed_night") == .securityNight)
        #expect(ColorFamily.security(alarmState: "disarmed") == .securityDisarmed)
        #expect(ColorFamily.security(alarmState: "triggered") == .securityTriggered)
        #expect(ColorFamily.security(alarmState: "arming") == nil)
        #expect(ColorFamily.security(alarmState: nil) == nil)
    }

    @Test func mixBlendsEachChannel() {
        #expect(ColorFamily.mix(0xFFFFFF, 0x000000, 1) == 0xFFFFFF)
        #expect(ColorFamily.mix(0xFFFFFF, 0x000000, 0) == 0x000000)
        #expect(ColorFamily.mix(0xFF0000, 0x0000FF, 0.5) == 0x800080)
    }
}
