#if DEBUG
import HassDesign
import SwiftUI

/// Gallery page for direction G's foundation (`.agents/design/direction-g.md`): the arc spinner, status chips,
/// tile faces and the light dragger, modules, the primary button, and a sheet with the bottom glass section bar.
///
/// Drawn on a stand-in wallpaper (a photo-like gradient under G's scrim) so screenshots and the rendered contrast
/// audit see the same layering as a page. Launch with `FENTON_GALLERY=direction-g`.
struct DirectionGGallery: View {
    @State private var lastAction = "none"
    @State private var brightness = 60
    /// `-directionGSheet open` presents the section sheet at launch, so a journey audits it (also at AX5) without a tap.
    @State private var showsSheet = UserDefaults.standard.string(forKey: "directionGSheet") == "open"
    /// `-directionGOrder lower` puts the modules, spinners and buttons first, so a journey audits them unscrolled
    /// (scrolled, the tiles under the header fade read as failing contrast).
    private let lowerFirst = UserDefaults.standard.string(forKey: "directionGOrder") == "lower"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HassTokens.Spacing.xl) {
                if !GalleryEnvironment.isClean {
                    GalleryLastCall(text: lastAction, title: "Last action")
                        .padding(HassTokens.Spacing.m)
                        .module()
                }
                if lowerFirst {
                    lower
                    chips
                    tiles
                } else {
                    chips
                    tiles
                    lower
                }
            }
            .padding(HassTokens.Spacing.l)
        }
        .background { DirectionGGalleryWallpaper() }
        // Still arcs, so XCUITest sees the app go idle (`arcSpinnersPaused`); `-directionGAnimate YES` turns them.
        .environment(\.arcSpinnersPaused, !UserDefaults.standard.bool(forKey: "directionGAnimate"))
        .navigationTitle("Direction G")
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showsSheet) {
            DirectionGGallerySheet().hassSheet()
        }
    }

    // MARK: Sections

    @ViewBuilder
    private var lower: some View {
        modules
        spinners
        PrimaryButton("Open Section Sheet", systemImage: "rectangle.bottomthird.inset.filled") {
            showsSheet = true
        }
        .accessibilityIdentifier("g.primary")
        PrimaryButton("Start Watering", family: .water) { lastAction = "start watering" }
            .accessibilityIdentifier("g.primary.water")
    }

    private var chips: some View {
        section("Status Chips") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: HassTokens.Spacing.s) {
                    chip("Lights", "3 On", "lightbulb.2", .lights, true)
                    chip("Security", "Armed Home", "shield.lefthalf.filled", .securityHome, true)
                    chip("Climate", "68–71°", "thermometer.medium", .climate, true)
                    chip("Occupancy", "Occupied", "figure.walk", .occupancy, true)
                    chip("Contact Sensors", "Back Deck Open", "door.left.hand.open", .contact, true)
                    chip("Air Quality", "AQI 21 · PM2.5 3", "aqi.medium", .air, true)
                    chip("Doors", "All Closed", "door.left.hand.closed", .contact, false)
                }
            }
        }
    }

    private func chip(_ title: String, _ summary: String, _ symbol: String, _ family: ColorFamily, _ active: Bool) -> some View {
        StatusChipButton(title: title, summary: summary, symbol: symbol, family: family, isActive: active) {
            lastAction = "chip \(title)"
        }
        .accessibilityIdentifier("g.chip.\(title)")
    }

    private var tiles: some View {
        section("Tiles") {
            DynamicGridLayout(minCellWidth: 150, maxColumns: 4, equalRowHeights: true) {
                BrightnessTile(title: "Kitchen Lights", tint: ColorFamily.lights.glyph, percent: brightness,
                               onPower: { on in brightness = on ? 100 : 0; lastAction = "power \(on)" },
                               onBrightness: { value in brightness = value; lastAction = "brightness \(value)" })
                    .accessibilityIdentifier("g.tile.light")
                tile("Office Lamp", "Off", "lamp.desk", .lights, false)
                tile("Living Room Purifier", "Auto · 42%", "air.purifier", .air, true)
                tile("Bath Fan", "Off", "fan", .air, false)
                tile("Living Room TV", "Netflix", "tv", .media, true)
                tile("Towel Rack", "On", "powerplug", .power, true)
                GlassTile(title: "Dishwasher", subtitle: "Washing · 40%", symbol: "dishwasher", family: .cleaning,
                          isActive: true, progress: 0.4) { lastAction = "tile Dishwasher" }
                    .accessibilityIdentifier("g.tile.Dishwasher")
                tile("Master Bedroom Closet", "Occupied", "figure.walk", .occupancy, true)
                tile("Back Deck Door", "Open", "door.left.hand.open", .contact, true)
                GlassTile(title: "Garage Door", subtitle: "Didn't Respond", symbol: "door.garage.closed",
                          family: .contact, isActive: false, isError: true) { lastAction = "tile Garage Door" }
                    .accessibilityIdentifier("g.tile.Garage Door")
                tile("Sprinklers", "Next Run 6:00 AM", "sprinkler.and.droplets", .water, false)
                GlassTile(title: "Unassigned Device", subtitle: "On", symbol: "switch.2", tint: .teal,
                          isActive: true) { lastAction = "tile Unassigned" }
                    .accessibilityIdentifier("g.tile.Unassigned")
            }
            .equalHeightTiles()
        }
    }

    private func tile(_ title: String, _ subtitle: String, _ symbol: String, _ family: ColorFamily, _ active: Bool) -> some View {
        GlassTile(title: title, subtitle: subtitle, symbol: symbol, family: family, isActive: active) {
            lastAction = "tile \(title)"
        }
        .accessibilityIdentifier("g.tile.\(title)")
    }

    private var modules: some View {
        section("Modules") {
            VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
                Text("Thin Module").font(.headline)
                Text("Cards, inset lists and tiles on the wallpaper.")
                    .font(.subheadline)
                    .foregroundStyle(HassTokens.Surface.secondaryOnModule)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(HassTokens.Spacing.l)
            .module()
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("g.module.thin")
            VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
                Text("3 Chores Overdue").font(.headline).foregroundStyle(HassTokens.Ink.danger)
                Text("Milk Expires Tomorrow").font(.subheadline).foregroundStyle(HassTokens.Ink.warning)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(HassTokens.Spacing.l)
            .module(.dense)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("g.module.dense")
        }
    }

    private var spinners: some View {
        section("Loading") {
            HStack(spacing: HassTokens.Spacing.xl) {
                ArcSpinner(.page)
                ArcSpinner(.compact, label: "Updating")
                ArcSpinner(.inline, label: "Sending Open").foregroundStyle(HassTokens.Ink.action)
                ProgressView("Loading Recipes").progressViewStyle(.arc(.compact))
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("g.spinners")
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.m) {
            Text(title)
                .font(.title3.bold())
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }
}

/// A sheet with tiles on the sheet surface and the bottom glass section bar. Launch with `FENTON_APPEARANCE=light` to
/// draw it in the light appearance (`SystemAppearance`); the page behind stays dark.
private struct DirectionGGallerySheet: View {
    enum Section: String, CaseIterable, Identifiable {
        case controls = "Controls", families = "Families", apps = "Apps", settings = "Settings"
        var id: Self { self }
    }

    /// `-directionGSheetSection Families` picks the first section, so a journey audits each one at launch.
    @State private var section = Section(rawValue: UserDefaults.standard.string(forKey: "directionGSheetSection") ?? "") ?? .controls

    var body: some View {
        HassModal("Living Room TV") {
            ScrollView {
                VStack(alignment: .leading, spacing: HassTokens.Spacing.l) {
                    switch section {
                    case .controls: controls
                    case .families: families
                    case .apps:
                        DynamicGridLayout(minCellWidth: 150, maxColumns: 4, equalRowHeights: true) {
                            GlassTile(title: "Netflix", symbol: "play.rectangle", family: .media, isActive: false, kind: .command)
                        }
                        .equalHeightTiles()
                    case .settings: settings
                    }
                }
                .padding(HassTokens.Spacing.l)
            }
            .modalTabBar(Section.allCases, label: "TV sections", title: \.rawValue, selection: $section,
                         identifier: "g.sheet.tabs")
        }
    }

    /// Filled, off, lit, error, tinted and washed faces on the sheet's cell.
    private var controls: some View {
        DynamicGridLayout(minCellWidth: 150, maxColumns: 4, equalRowHeights: true) {
            GlassTile(title: "Power", subtitle: "On", symbol: "power", family: .media, isActive: true)
            GlassTile(title: "Mute", subtitle: "Off", symbol: "speaker.slash", family: .media, isActive: false)
            GlassTile(title: "Floor Lamp", subtitle: "Off", symbol: "lamp.floor", family: .lights, isActive: false)
            GlassTile(title: "Table Lamp", subtitle: "60%", symbol: "lamp.table", family: .lights, isActive: true)
            GlassTile(title: "Bath Fan", subtitle: "Didn't Respond", symbol: "fan", family: .air, isActive: false, isError: true)
            GlassTile(title: "Unassigned Device", subtitle: "On", symbol: "switch.2", tint: .teal, isActive: true)
            GlassTile(title: "Dishwasher", subtitle: "Washing · 40%", symbol: "dishwasher", family: .cleaning,
                      isActive: true, progress: 0.4)
            GlassTile(title: "Armed Home", subtitle: "Since 6:51 PM", symbol: "house", family: .securityHome,
                      isActive: false, wash: ColorFamily.securityHome.fill)
        }
        .equalHeightTiles()
    }

    /// Every colour family off, so each light variant's glyph is on screen.
    private var families: some View {
        DynamicGridLayout(minCellWidth: 150, maxColumns: 4, equalRowHeights: true) {
            ForEach(ColorFamily.allCases, id: \.self) { family in
                GlassTile(title: family.rawValue.capitalized, subtitle: "Off", symbol: "circle.hexagongrid", family: family,
                          isActive: false)
            }
        }
        .equalHeightTiles()
    }

    /// An inset list with a chevron row, a value row and a plain row, on the sheet's cell.
    private var settings: some View {
        ModuleList {
            ModuleRow("Sleep Timer", subtitle: "Off", symbol: "moon", glyph: ColorFamily.media.offGlyph, showsChevron: true)
            ModuleRow("Input", symbol: "rectangle.on.rectangle", glyph: ColorFamily.media.glyph) {
                Text("HDMI 2").foregroundStyle(HassTokens.Surface.secondaryInSheet)
            }
            ModuleRow("Reset Remote", symbol: "arrow.counterclockwise")
        }
    }
}

/// A stand-in for the house photo: warm lit windows over a dusk sky, under G's scrim, so the gallery shows the
/// worst case the scrim is tuned for without a server.
private struct DirectionGGalleryWallpaper: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.42, green: 0.55, blue: 0.70), Color(red: 0.86, green: 0.70, blue: 0.45),
                                    Color(red: 0.30, green: 0.36, blue: 0.26), Color(red: 0.16, green: 0.18, blue: 0.14)],
                           startPoint: .top, endPoint: .bottom)
            HouseBackdropStyle.scrim
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
#endif
