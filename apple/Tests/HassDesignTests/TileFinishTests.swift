import Foundation
@testable import HassDesign
import SwiftUI
import Testing

/// The tile finish proposals (`.agents/design/direction-g.md`, Tile finish): tokens, the accessibility fallback and the
/// rendered contrast of every finish on the wallpaper's lightest and darkest regions.
@MainActor
struct TileFinishTests {
    typealias RGB = (r: Double, g: Double, b: Double)

    /// The lightest wallpaper under the scrim that white text still reads on at 4.5:1 (sRGB grey 0.46, 4.7:1 for white), and
    /// the darkest, the web shell's `#111723`.
    static let lightest: RGB = (0.46, 0.46, 0.46)
    static let darkest: RGB = (17 / 255, 23 / 255, 35 / 255)

    // MARK: Tokens

    @Test func theShippedFinishIsSolidAndTheProposalsAreNot() {
        #expect(TileFinish.standard == .solid, "A finish ships only after the owner picks one")
        #expect(EnvironmentValues().tileFinish == .solid)
        #expect(TileFinish.allCases.count == 4)
        #expect(Set(TileFinish.allCases.map(\.title)).count == 4)
        #expect(Set(TileFinish.allCases.map(\.summary)).count == 4)
        #expect(TileFinish.frostedModule.usesGlyphDisc)
        #expect(!TileFinish.tintedGlass.usesGlyphDisc)
    }

    @Test func aSheetIsOpaqueBecauseThereIsNoWallpaperToShowThrough() {
        for finish in TileFinish.allCases {
            let sheet = finish.tokens(on: .sheet)
            #expect(sheet.fillOpacity == 1, "\(finish)")
            #expect(sheet.offVeil == 0, "\(finish)")
        }
    }

    @Test func theFrostedFinishesLetTheWallpaperTintTheFillOnAPage() {
        #expect(TileFinish.solid.tokens(on: .page).fillOpacity == 1)
        for finish in [TileFinish.tintedGlass, .webPort] {
            let page = finish.tokens(on: .page)
            #expect(page.fillOpacity < 1 && page.fillOpacity >= 0.7, "\(finish) \(page.fillOpacity)")
            #expect(page.rimTop > 0)
        }
        let module = TileFinish.frostedModule.tokens(on: .page)
        #expect(module.edgeGlow > 0 && module.edgeWash > 0)
    }

    @Test func reduceTransparencyAndIncreaseContrastFallBackToSolid() {
        for finish in TileFinish.allCases {
            #expect(TileFinish.effective(finish, reduceTransparency: true, increasedContrast: false) == .solid)
            #expect(TileFinish.effective(finish, reduceTransparency: false, increasedContrast: true) == .solid)
            #expect(TileFinish.effective(finish, reduceTransparency: false, increasedContrast: false) == finish)
        }
    }

    // MARK: Rendering

    @Test(arguments: TileFinish.allCases, [TileSurface.page, .sheet])
    func everyFinishRendersEveryFaceOnEverySurface(_ finish: TileFinish, _ surface: TileSurface) {
        for scheme in [ColorScheme.dark, .light] { renderFaces(finish, surface, scheme) }
    }

    private func renderFaces(_ finish: TileFinish, _ surface: TileSurface, _ scheme: ColorScheme) {
        let faces: [(String, ColorFamily, Bool, Bool, UInt32?)] = [
            ("Office Lamp", .lights, false, false, nil), ("Table Lamp", .lights, true, false, nil),
            ("Purifier", .air, true, false, nil), ("Towel Rack", .power, true, false, nil),
            ("Garage", .contact, false, true, nil), ("Kitchen", .neutral, false, false, 0x547F12),
        ]
        for (title, family, active, error, fill) in faces {
            let tile = GlassTileFace(title: title, subtitle: "State", symbol: "lightbulb", tint: .gray, family: family, fillRGB: fill,
                                     isActive: active, isError: error, showsChevron: fill != nil, level: family == .power ? 0.4 : nil)
                .environment(\.tileSurface, surface)
                .environment(\.colorScheme, scheme)
                .tileFinish(finish)
                .frame(width: 170)
            #expect(ImageRenderer(content: tile).cgImage != nil, "\(finish) \(title)")
            let accessible = tile.environment(\.dynamicTypeSize, .accessibility5)
            #expect(ImageRenderer(content: accessible).cgImage != nil)
        }
    }

    // MARK: Contrast

    /// Every finish keeps the page's text at 4.5:1 (state text at 85% ink for the frosted ones) and its off glyphs at 3:1 on the
    /// wallpaper's lightest and darkest regions, measured on rendered pixels at the right edge of the tile (clear of the text,
    /// at the heights text sits).
    @Test(arguments: TileFinish.allCases)
    func inkHoldsContrastOnTheLightestAndDarkestWallpaper(_ finish: TileFinish) {
        for backdrop in [Self.lightest, Self.darkest] {
            // Off
            for ground in samples(finish, .off, backdrop: backdrop) {
                let secondary = finish == .solid ? 0.68 : 0.85
                expectRatio(white, over: ground, atLeast: 4.5, "\(finish) off title")
                expectRatio(blend((235 / 255, 235 / 255, 245 / 255), over: ground, alpha: secondary), over: ground, atLeast: 4.5,
                            "\(finish) off state")
            }
            // On, white ink on every white-ink family fill and every room: B keeps white ink on its neutral module.
            let fills = ColorFamily.allCases.compactMap { family in family.spec.darkInk ? nil : family.spec.fill.map { (family.rawValue, $0) } }
                + RoomPalette.fills.map { ($0.key, $0.value) }
            for (name, fill) in fills {
                let style: TileFaceStyle = ColorFamily(rawValue: name).map { .filled($0) } ?? .colored(fill)
                for ground in samples(finish, style, backdrop: backdrop) {
                    expectRatio(white, over: ground, atLeast: 4.5, "\(finish) \(name) title")
                    expectRatio(blend(white, over: ground, alpha: finish.usesGlyphDisc ? 0.85 : style.isColored ? 1 : 0.92), over: ground, atLeast: 4.5,
                                "\(finish) \(name) state")
                }
            }
            // An error: the page red on the dense ground.
            for ground in samples(finish, .error, backdrop: backdrop) {
                expectRatio(hex(HassTokens.Palette.red), over: ground, atLeast: 4.5, "\(finish) error")
            }
            // Off glyphs: the family colour mixed toward grey, 3:1 where the shipped finish reaches it (the lightest region is
            // the extreme the scrim is tuned for), and never more than 15% under the shipped finish's ratio.
            for family in ColorFamily.allCases where family != .neutral {
                let shipped = samples(.solid, .off, backdrop: backdrop).map { ratio(hex(family.offGlyphRGB(.dark)), $0) }.min() ?? 0
                let glyph = hex(family.offGlyphRGB(.dark, keep: finish.offGlyphKeep))
                for sample in samples(finish, .off, backdrop: backdrop) {
                    // Finish B sets the glyph in a darker disc.
                    let ground = finish.usesGlyphDisc ? blend((0, 0, 0), over: sample, alpha: TileFinish.offDiscShade.dark) : sample
                    expectRatio(glyph, over: ground, atLeast: min(3, shipped * 0.85), "\(finish) \(family) off glyph")
                }
            }
        }
    }

    // MARK: Helpers

    private var white: RGB { (1, 1, 1) }

    private func hex(_ value: UInt32) -> RGB {
        (Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255, Double(value & 0xFF) / 255)
    }

    private func blend(_ ink: RGB, over ground: RGB, alpha: Double) -> RGB {
        (ink.r * alpha + ground.r * (1 - alpha), ink.g * alpha + ground.g * (1 - alpha), ink.b * alpha + ground.b * (1 - alpha))
    }

    private func luminance(_ c: RGB) -> Double {
        func linear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b)
    }

    private func ratio(_ a: RGB, _ b: RGB) -> Double {
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    private func expectRatio(_ ink: RGB, over ground: RGB, atLeast minimum: Double, _ label: String,
                             sourceLocation: SourceLocation = #_sourceLocation) {
        let value = ratio(ink, ground)
        #expect(value >= minimum, "\(label): \(value):1 over \(ground)", sourceLocation: sourceLocation)
    }

    /// The ground the finish draws behind text, read from rendered pixels at the right edge at three heights.
    private func samples(_ finish: TileFinish, _ style: TileFaceStyle, backdrop: RGB) -> [RGB] {
        // The shipped finish has no frosted ground to render, so its numbers come from the module and fill directly.
        if finish == .solid { return solidSamples(style, backdrop: backdrop) }
        let size = CGSize(width: 170, height: 90)
        let view = ZStack {
            Color(.sRGB, red: backdrop.r, green: backdrop.g, blue: backdrop.b)
            FrostedGround(finish: finish, style: style, surface: .page, appearance: .dark,
                          tint: .gray, wash: nil, level: nil, levelTint: nil)
                .clipShape(RoundedRectangle(cornerRadius: HassTokens.Radius.tile, style: .continuous))
        }
        .frame(width: size.width, height: size.height)
        .environment(\.colorScheme, .dark)
        let image = ImageRenderer(content: view)
        image.scale = 1
        guard let cg = image.cgImage else { return [] }
        return [0.35, 0.5, 0.85].compactMap { fraction in pixel(cg, x: Int(size.width * 0.85), y: Int(size.height * fraction)) }
    }

    /// The solid finish's ground: the thin module (66%) over the backdrop for off and error, the fill itself otherwise.
    private func solidSamples(_ style: TileFaceStyle, backdrop: RGB) -> [RGB] {
        switch style {
        case .off, .tinted: [blend(hex(HassTokens.Palette.moduleThin), over: backdrop, alpha: 0.66)]
        case .error: [blend(hex(HassTokens.Palette.moduleDense), over: backdrop, alpha: 0.78)]
        case let .filled(family): [hex(family.spec.fill ?? 0)]
        case let .colored(fill): [hex(fill)]
        case .lit: [hex(0xEADBC4)]
        }
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) -> RGB? {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let drawn = data.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                                          bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        guard drawn, x < image.width, y < image.height else { return nil }
        let i = (y * image.width + x) * 4
        return (Double(data[i]) / 255, Double(data[i + 1]) / 255, Double(data[i + 2]) / 255)
    }
}
