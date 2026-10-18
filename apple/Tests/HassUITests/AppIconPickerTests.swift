#if os(macOS)
import AppKit
import FentonActivityModel
import Foundation
@preconcurrency import HAKit
import HassCore
import HassDesign
@testable import HassUI
import ImageIO
import SwiftUI
import Testing

/// A stand-in for `UIApplication`'s alternate-icon calls.
@MainActor
final class FakeIconSystem {
    var name: String?
    var supports = true
    var failure: (any Error)?
    private(set) var requested: [String?] = []

    init(name: String? = nil) { self.name = name }

    var platform: AppIconPlatform {
        AppIconPlatform(
            supportsAlternateIcons: { self.supports },
            currentName: { self.name },
            setName: { requested in
                self.requested.append(requested)
                // The real call suspends until iOS has taken the request.
                await Task.yield()
                if let failure = self.failure { throw failure }
                self.name = requested
            })
    }
}

struct IconFailure: LocalizedError {
    var errorDescription: String? { "The system said no." }
}

/// The selection model behind Settings → App Icon, over a fake system.
@MainActor
struct AppIconPickerModelTests {
    @Test func startsOnTheInstalledIcon() {
        #expect(AppIconPickerModel(platform: FakeIconSystem().platform, iconStore: ActivityAppIconStore(defaults: nil)).selected == .navySky)
        #expect(AppIconPickerModel(platform: FakeIconSystem(name: "AppIcon-PlumLilac").platform, iconStore: ActivityAppIconStore(defaults: nil)).selected == .plumLilac)
        #expect(AppIconPickerModel(platform: FakeIconSystem(name: "AppIcon-Gone").platform, iconStore: ActivityAppIconStore(defaults: nil)).selected == .navySky, "An icon an update removed")
    }

    @Test func choosingAnAlternateInstallsItsNameAndMovesTheCheck() async {
        let system = FakeIconSystem()
        let model = AppIconPickerModel(platform: system.platform, iconStore: ActivityAppIconStore(defaults: nil))
        await model.select(.tealMint)
        #expect(system.requested == ["AppIcon-TealMint"])
        #expect(model.selected == .tealMint)
        #expect(model.isSelected(.tealMint) && !model.isSelected(.navySky))
        #expect(!model.isChanging && model.failureMessage == nil)
    }

    @Test func everyInstalledChoiceIsSharedWithTheLiveActivityThroughTheAppGroup() async throws {
        let suite = "test.appiconpicker.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ActivityAppIconStore(defaults: defaults)
        let system = FakeIconSystem()
        let model = AppIconPickerModel(platform: system.platform, iconStore: store)
        await model.select(.burgundyRose)
        #expect(store.choice == "burgundyRose")
        await model.select(.navySky)
        #expect(store.choice == "navySky", "restoring the default writes it too")
        system.failure = IconFailure()
        await model.select(.tealMint)
        #expect(store.choice == "navySky", "a refused change leaves the stored choice alone")
        // The launch sync writes whatever is installed.
        AppIconAppGroupSync.write(platform: FakeIconSystem(name: "AppIcon-PlumLilac").platform, store: store)
        #expect(store.choice == "plumLilac")
        AppIconAppGroupSync.writeInstalledChoice()
    }

    @Test func choosingTheDefaultPassesNilToRestoreIt() async {
        let system = FakeIconSystem(name: "AppIcon-MidnightGold")
        let model = AppIconPickerModel(platform: system.platform, iconStore: ActivityAppIconStore(defaults: nil))
        await model.select(.navySky)
        #expect(system.requested == [nil])
        #expect(model.selected == .navySky)
    }

    @Test func choosingTheInstalledIconDoesNothing() async {
        let system = FakeIconSystem()
        let model = AppIconPickerModel(platform: system.platform, iconStore: ActivityAppIconStore(defaults: nil))
        await model.select(.navySky)
        #expect(system.requested.isEmpty)
    }

    @Test func aRefusalKeepsTheSelectionAndRaisesTheAlert() async {
        let system = FakeIconSystem()
        system.failure = IconFailure()
        let model = AppIconPickerModel(platform: system.platform, iconStore: ActivityAppIconStore(defaults: nil))
        await model.select(.burgundyRose)
        #expect(model.selected == .navySky)
        #expect(model.failureMessage == "The icon wasn't changed to Burgundy + Rose. The system said no.")
        #expect(!model.isChanging, "A failed change frees the taps again")
        #expect(model.isShowingFailure)
        model.isShowingFailure = true
        #expect(model.failureMessage != nil, "Only dismissing clears it")
        model.isShowingFailure = false
        #expect(model.failureMessage == nil && !model.isShowingFailure)
        system.failure = nil
        await model.select(.burgundyRose)
        #expect(model.selected == .burgundyRose)
    }

    @Test func aTapDuringAChangeIsIgnored() async {
        let system = FakeIconSystem()
        let model = AppIconPickerModel(platform: system.platform, iconStore: ActivityAppIconStore(defaults: nil))
        async let first: Void = model.select(.indigoPeriwinkle)
        async let second: Void = model.select(.forestGreen)
        _ = await (first, second)
        #expect(system.requested.count == 1, "The second tap landed while the first change was in flight")
    }

    @Test func supportIsReadOnceFromTheSystem() {
        let system = FakeIconSystem()
        #expect(AppIconPickerModel(platform: system.platform, iconStore: ActivityAppIconStore(defaults: nil)).isSupported)
        system.supports = false
        #expect(!AppIconPickerModel(platform: system.platform, iconStore: ActivityAppIconStore(defaults: nil)).isSupported)
    }

    @Test func theStoreBuildsTheModelOnceAndReadsTheSystemOnce() {
        let system = FakeIconSystem(name: "AppIcon-PlumLilac")
        let store = AppIconPickerModelStore()
        let first = store.model(for: system.platform)
        system.name = "AppIcon-TealMint"
        #expect(store.model(for: system.platform) === first, "A redraw reuses the model and does not read the icon again")
        #expect(first.selected == .plumLilac)
    }

    @Test func theMacTestHostHasNoAlternateIcons() async throws {
        let model = AppIconPickerModel(platform: .system)
        #expect(!model.isSupported)
        #expect(model.selected == .navySky)
        try await AppIconPlatform.system.setName("AppIcon-TealMint")
    }
}

/// The icon art: it draws the mockup's glyph in each pair's colour, in three appearances, and the committed catalog
/// PNGs are what it renders.
@MainActor
struct AppIconArtworkTests {
    /// The pixels of `AppIconArtwork` at `side` × `side`.
    static func render(_ choice: AppIconChoice, _ appearance: AppIconArtwork.Appearance, side: Int) -> Pixels? {
        let art = AppIconArtwork(tint: choice.tint, tintOpacity: AppIconChoice.tintOpacity,
                                 glyph: choice.glyph, appearance: appearance)
            .frame(width: CGFloat(side), height: CGFloat(side))
        let renderer = ImageRenderer(content: art)
        renderer.scale = 1
        return renderer.cgImage.flatMap(Pixels.init)
    }

    /// An image read back as RGBA bytes.
    struct Pixels {
        let side: Int
        let bytes: [UInt8]

        init?(_ image: CGImage) {
            side = image.width
            var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: &data, width: image.width, height: image.height, bitsPerComponent: 8,
                                          bytesPerRow: image.width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            bytes = data
        }

        func rgb(x: Int, y: Int) -> (Int, Int, Int) {
            let index = (y * side + x) * 4
            return (Int(bytes[index]), Int(bytes[index + 1]), Int(bytes[index + 2]))
        }
    }

    /// The pixel at a glyph coordinate (100-unit box, 80% of the icon's width, centred).
    static func glyphPoint(_ x: Double, _ y: Double, side: Int) -> (Int, Int) {
        let s = Double(side), box = s * 0.80
        let origin = (s - box) / 2
        return (Int(origin + x * box / 100), Int(origin + y * box / 100))
    }

    static func near(_ pixel: (Int, Int, Int), _ rgb: UInt32, tolerance: Int = 3) -> Bool {
        abs(pixel.0 - Int((rgb >> 16) & 0xFF)) <= tolerance && abs(pixel.1 - Int((rgb >> 8) & 0xFF)) <= tolerance
            && abs(pixel.2 - Int(rgb & 0xFF)) <= tolerance
    }

    @Test(arguments: AppIconChoice.allCases)
    func theHouseAndHeartAreDrawnInThePairsColourAndTheRingIsTheGlassAroundThem(_ choice: AppIconChoice) throws {
        let side = 512
        let pixels = try #require(Self.render(choice, .standard, side: side))
        // The house wall (above the window, left of the heart): the glyph colour.
        let wall = Self.glyphPoint(50, 52, side: side)
        #expect(Self.near(pixels.rgb(x: wall.0, y: wall.1), choice.glyph), "\(choice) house")
        // The window pane is cut out: the glass shows through, not the glyph.
        let pane = Self.glyphPoint(42, 76, side: side)
        let glass = pixels.rgb(x: pane.0, y: pane.1)
        #expect(!Self.near(glass, choice.glyph, tolerance: 40), "\(choice) window")
        // The heart's centre: the glyph colour again.
        let heart = Self.glyphPoint(55 + 0.40 * 50, 60 + 0.40 * 45, side: side)
        #expect(Self.near(pixels.rgb(x: heart.0, y: heart.1), choice.glyph), "\(choice) heart")
        // The ring cuts the heart out of the house and is the glass itself (the colour of the window pane beside it).
        let ring = Self.glyphPoint(55 + 0.40 * 8 - 1.6, 72, side: side)
        let ringPixel = pixels.rgb(x: ring.0, y: ring.1)
        #expect(!Self.near(ringPixel, choice.glyph, tolerance: 40), "\(choice) ring is not glyph")
        #expect(abs(ringPixel.0 - glass.0) <= 8 && abs(ringPixel.1 - glass.1) <= 8 && abs(ringPixel.2 - glass.2) <= 8,
                "\(choice) ring \(ringPixel) matches the glass \(glass)")
    }

    @Test func theGlassFillsTheWholeSquareWithNoFrameOrInsetTile() throws {
        // Owner correction, 2026-10-17: no inset tile and no visible outer frame. The colour a hair inside the edge
        // equals the colour a tenth in, and the corners are the tint (iOS masks them), not the dusk glow.
        let side = 512
        for choice in AppIconChoice.allCases {
            let pixels = try #require(Self.render(choice, .standard, side: side))
            for y in [side / 4, side / 2, side * 3 / 4] {
                let edge = pixels.rgb(x: 3, y: y), inner = pixels.rgb(x: side / 10, y: y)
                #expect(abs(edge.0 - inner.0) <= 6 && abs(edge.1 - inner.1) <= 6 && abs(edge.2 - inner.2) <= 6,
                        "\(choice) edge \(edge) vs inner \(inner) at y=\(y): no frame")
            }
            let corner = pixels.rgb(x: 2, y: side - 3)
            let tint = (Int((choice.tint >> 16) & 0xFF), Int((choice.tint >> 8) & 0xFF), Int(choice.tint & 0xFF))
            // Tint at 86% over the glow: within the glow's reach (14% of at most 255) of the tint.
            #expect(abs(corner.0 - tint.0) <= 60 && abs(corner.1 - tint.1) <= 60 && abs(corner.2 - tint.2) <= 60,
                    "\(choice) corner \(corner) is the tint \(tint)")
        }
    }

    @Test func fullBleedWithNoRoundedOuterCorners() throws {
        // iOS applies the corner mask; the art must fill the square, corners included (HIG App icons).
        let side = 256
        let pixels = try #require(Self.render(.navySky, .standard, side: side))
        for (x, y) in [(0, 0), (side - 1, 0), (0, side - 1), (side - 1, side - 1)] {
            let alpha = pixels.bytes[(y * side + x) * 4 + 3]
            #expect(alpha == 255, "corner \(x),\(y) is opaque")
        }
    }

    @Test(arguments: AppIconChoice.allCases)
    func theGlyphIsEightyPercentWideAndClearsTheIconMask(_ choice: AppIconChoice) throws {
        // The glyph's extents (roof eaves at the sides, the heart ring bottom right) must sit well inside the iOS corner
        // mask, a continuous rounded rectangle of about 22.4% of the side.
        let side = 512
        let pixels = try #require(Self.render(choice, .standard, side: side))
        let inset = Double(side) * 0.03
        let mask = CGPath(roundedRect: CGRect(x: 0, y: 0, width: side, height: side).insetBy(dx: inset, dy: inset),
                          cornerWidth: Double(side) * 0.2237, cornerHeight: Double(side) * 0.2237, transform: nil)
        var minX = side, maxX = 0, minY = side, maxY = 0
        var outside = 0
        for y in 0..<side {
            for x in 0..<side where Self.near(pixels.rgb(x: x, y: y), choice.glyph, tolerance: 2) {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                if !mask.contains(CGPoint(x: x, y: y)) { outside += 1 }
            }
        }
        #expect(outside == 0, "\(choice): \(outside) glyph pixels outside the mask inset by 3%")
        let width = Double(maxX - minX) / Double(side)
        #expect(width > 0.62 && width < 0.80, "\(choice) glyph spans \(width) of the width")
        #expect(Double(minX) / Double(side) > 0.12 && Double(maxX) / Double(side) < 0.90, "\(choice) side margins")
        #expect(Double(minY) / Double(side) > 0.15 && Double(maxY) / Double(side) < 0.90, "\(choice) top and bottom margins")
    }

    @Test func darkIsDeeperThanStandardAndTintedIsGrey() throws {
        let side = 256
        let standard = try #require(Self.render(.navySky, .standard, side: side))
        let dark = try #require(Self.render(.navySky, .dark, side: side))
        let tinted = try #require(Self.render(.navySky, .tinted, side: side))
        func luminance(_ p: (Int, Int, Int)) -> Int { p.0 + p.1 + p.2 }
        // The ground at the corners and the amber glow low right.
        for (x, y) in [(4, 4), (side - 5, side - 5), (side * 3 / 4, side * 4 / 5 + 20)] {
            #expect(luminance(dark.rgb(x: x, y: y)) < luminance(standard.rgb(x: x, y: y)), "dark is darker at \(x),\(y)")
        }
        // Tinted has no colour at all, and its glyph is the brightest thing on it.
        for (x, y) in [(4, 4), (side / 2, side / 2), Self.glyphPoint(50, 52, side: side), (side - 5, side - 5)] {
            let p = tinted.rgb(x: x, y: y)
            #expect(abs(p.0 - p.1) <= 2 && abs(p.1 - p.2) <= 2, "tinted is grey at \(x),\(y)")
        }
        let glyph = Self.glyphPoint(50, 52, side: side)
        #expect(luminance(tinted.rgb(x: glyph.0, y: glyph.1)) > 700)
    }

    @Test func theCatalogHoldsAnOpaqueSetForEveryChoice() throws {
        let catalog = Self.catalog
        for choice in AppIconChoice.allCases {
            let folder = catalog.appending(path: "\(choice.assetName).appiconset", directoryHint: .isDirectory)
            let contents = try String(contentsOf: folder.appending(path: "Contents.json"), encoding: .utf8)
            for file in ["light.png", "dark.png", "tinted.png"] {
                #expect(contents.contains(file), "\(choice.assetName) lists \(file)")
                let source = try #require(CGImageSourceCreateWithURL(folder.appending(path: file) as CFURL, nil), "\(choice.assetName)/\(file)")
                let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
                #expect(image.width == 1024 && image.height == 1024, "\(choice.assetName)/\(file) is 1024 × 1024")
                // The App Store rejects an icon with an alpha channel.
                #expect([.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo), "\(choice.assetName)/\(file) has no alpha")
            }
            #expect(contents.contains("\"value\" : \"dark\"") && contents.contains("\"value\" : \"tinted\""))
        }
    }

    @Test func theCommittedLightIconsAreWhatTheArtRenders() throws {
        // `tools/render_app_icons.sh` writes the catalog; this fails when the art or a colour changed and the PNGs did not.
        for choice in AppIconChoice.allCases {
            try Self.expectCatalogMatches(choice, "light", .standard)
        }
        try Self.expectCatalogMatches(.navySky, "dark", .dark)
        try Self.expectCatalogMatches(.navySky, "tinted", .tinted)
    }

    static var catalog: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Apps/iOS/Assets.xcassets", directoryHint: .isDirectory)
    }

    static func expectCatalogMatches(_ choice: AppIconChoice, _ file: String, _ appearance: AppIconArtwork.Appearance) throws {
        let url = catalog.appending(path: "\(choice.assetName).appiconset/\(file).png")
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let committed = try #require(Pixels(image))
        let rendered = try #require(render(choice, appearance, side: 1024))
        var differing = 0
        for index in stride(from: 0, to: committed.bytes.count, by: 4) {
            for channel in 0..<3 where abs(Int(committed.bytes[index + channel]) - Int(rendered.bytes[index + channel])) > 4 {
                differing += 1
                break
            }
        }
        // A tolerance of 0.1% of the pixels: the first `ImageRenderer` render in a process differs on a few edge pixels.
        #expect(differing < 1024 * 1024 / 1000, "\(choice.assetName)/\(file).png differs from the art in \(differing) pixels")
    }
}

/// The Settings row and the App Icon sheet, driven through the accessibility tree like the device journeys.
@MainActor
@Suite(.serialized, .enabled(if: AXWindow.isAvailable, "Needs accessibility permission for the test host"))
struct AppIconFlowTests {
    static let phone = CGSize(width: 402, height: 1800)

    func open(_ system: FakeIconSystem) async -> AXWindow {
        let session = AppSession(tokenStore: InMemoryTokenStore(), snapshotCache: EntitySnapshotCache(
            fileURL: FileManager.default.temporaryDirectory.appending(path: "app-icon-\(UUID()).json")))
        let store = EntityStore()
        let connection = HassConnection(server: .fentonHome, tokens: TokenManager(store: InMemoryTokenStore()), store: store)
        let driver = AXWindow(
            NavigationStack { SettingsScreen() }
                .environment(session)
                .environment(connection)
                .environment(store)
                .environment(\.appIconPlatform, system.platform),
            size: Self.phone)
        await driver.window.settle(0.8)
        return driver
    }

    @Test func theSettingsRowShowsTheInstalledIconAndOpensTheSheetWithEightChoices() async throws {
        let system = FakeIconSystem(name: "AppIcon-TealMint")
        let driver = await open(system)
        defer { driver.close() }
        let row = try #require(await driver.waitFor("settings.appIcon"), "the App Icon row")
        #expect(row.spoken.contains("App Icon") && row.spoken.contains("Teal + Mint"), "row reads: \(row.spoken)")
        #expect(row.frame.height >= 43, "44 pt target")
        // Its own Appearance section: after Vacation, before the household topics and the diagnostic Performance row.
        let list = await driver.nodes()
        let vacation = try #require(list.first { $0.identifier == "settings.vacation" })
        let topic = try #require(list.first { $0.identifier.hasPrefix("settings.topic.") })
        let performance = try #require(list.first { $0.identifier == "settings.performance" })
        #expect(vacation.frame.minY < row.frame.minY && row.frame.minY < topic.frame.minY, "Appearance sits above the household topics")
        #expect(row.frame.minY < performance.frame.minY, "and well before Performance")
        #expect(list.contains { $0.spoken == "Appearance" }, "under an Appearance header")
        #expect(await driver.press("settings.appIcon") { $0.contains { $0.identifier == "appIcon.choice.navySky" } })
        let nodes = await driver.nodes()
        for choice in AppIconChoice.allCases {
            let button = try #require(nodes.first { $0.identifier == "appIcon.choice.\(choice.rawValue)" }, "\(choice)")
            #expect(button.role == "AXButton")
            #expect(button.spoken.hasPrefix(choice.spokenName), "\(choice): \(button.spoken)")
            #expect(button.value == (choice == .tealMint ? "Selected" : "Not selected"), "\(choice) value \(button.value)")
            #expect(button.frame.height >= 44 && button.frame.width >= 44, "\(choice) target \(button.frame)")
        }
        let navy = try #require(nodes.first { $0.identifier == "appIcon.choice.navySky" })
        #expect(navy.spoken == "Navy and Sky, default", "The default is marked: \(navy.spoken)")
    }

    @Test func choosingAnIconSelectsItAndTheRowFollows() async throws {
        let system = FakeIconSystem()
        let driver = await open(system)
        defer { driver.close() }
        #expect(await driver.press("settings.appIcon") { $0.contains { $0.identifier == "appIcon.choice.plumLilac" } })
        #expect(await driver.press("appIcon.choice.plumLilac") { nodes in
            nodes.first { $0.identifier == "appIcon.choice.plumLilac" }?.value == "Selected"
        })
        #expect(system.requested == ["AppIcon-PlumLilac"])
        let nodes = await driver.nodes()
        #expect(nodes.first { $0.identifier == "appIcon.choice.navySky" }?.value == "Not selected")
        await driver.closeSheet()
        let row = try #require(await driver.waitFor("settings.appIcon"))
        #expect(row.spoken.contains("Plum + Lilac"), "row reads: \(row.spoken)")
    }

    @Test func aRefusedChangeShowsAnAlertAndKeepsTheSelection() async throws {
        let system = FakeIconSystem()
        system.failure = IconFailure()
        let driver = await open(system)
        defer { driver.close() }
        #expect(await driver.press("settings.appIcon") { $0.contains { $0.identifier == "appIcon.choice.espressoAmber" } })
        _ = await driver.press("appIcon.choice.espressoAmber")
        await driver.window.settle(0.8)
        #expect(system.requested == ["AppIcon-EspressoAmber"])
        #expect(await driver.shows("Couldn't Change Icon"), "The alert shows")
        let ok = await driver.waitFor("appIcon.failure.ok", timeout: 5)
        if let ok { _ = await driver.press(ok) }
        await driver.closeSheet()
        let row = try #require(await driver.waitFor("settings.appIcon"))
        #expect(row.spoken.contains("Navy + Sky"))
    }

    @Test func theRowIsHiddenWhereTheSystemCannotSwitchIcons() async {
        let system = FakeIconSystem()
        system.supports = false
        let driver = await open(system)
        defer { driver.close() }
        #expect(await driver.waitFor("settings.vacation") != nil, "the list is up")
        #expect(await driver.node("settings.appIcon") == nil)
        #expect(!(await driver.shows("Appearance")), "The empty section has no header either")
    }
}
#endif
