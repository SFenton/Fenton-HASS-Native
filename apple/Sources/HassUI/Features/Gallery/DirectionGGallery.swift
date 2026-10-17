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
    /// `-directionGOrder layouts` shows only the tile layout comparison, so a journey measures it unscrolled.
    private let layoutsOnly = UserDefaults.standard.string(forKey: "directionGOrder") == "layouts"
    /// `-directionGOrder finish` shows only the tile finish comparison, so a journey audits and a capture sees it unscrolled.
    private let finishOnly = UserDefaults.standard.string(forKey: "directionGOrder") == "finish"
    /// `-directionGFinish webPort` limits the finish comparison to one proposal (`solid`, `tintedGlass`, `frostedModule`, `webPort`).
    private let onlyFinish = UserDefaults.standard.string(forKey: "directionGFinish").flatMap(TileFinish.init(rawValue:))
    /// `-directionGLayout row` limits the comparison to one arrangement, so all six sample tiles fit on screen.
    private let onlyLayout = UserDefaults.standard.string(forKey: "directionGLayout").flatMap(TileLayout.init(rawValue:))

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HassTokens.Spacing.xl) {
                if !GalleryEnvironment.isClean {
                    GalleryLastCall(text: lastAction, title: "Last action")
                        .padding(HassTokens.Spacing.m)
                        .module()
                }
                if finishOnly {
                    finishes
                } else if layoutsOnly {
                    layouts
                } else if lowerFirst {
                    lower
                    chips
                    tiles
                    layouts
                } else {
                    chips
                    tiles
                    layouts
                    finishes
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
            DirectionGGallerySheet().hassSheet(height: .full)
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

    /// The four tile arrangements side by side on the same tiles (`TileLayout`), for the owner to compare and override.
    private var layouts: some View {
        section("Tile Layouts") {
            ForEach(TileLayout.allCases.filter { onlyLayout == nil || $0 == onlyLayout }) { layout in
                VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
                    Text(layout.title + (layout == .standard ? " (Shipped)" : ""))
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    DynamicGridLayout(minCellWidth: 150, maxColumns: 4, equalRowHeights: true) {
                        layoutTile(layout, "Office Lamp", "Off", "lamp.desk", .lights, false)
                        layoutTile(layout, "Living Room Purifier", "Auto · 42%", "air.purifier", .air, true)
                        layoutTile(layout, "Master Bedroom Closet", "Occupied", "figure.walk", .occupancy, true)
                        GlassTile(title: "Kitchen", symbol: "stove", family: .neutral, fillRGB: RoomPalette.fill(forRoom: "kitchen"),
                                  isActive: false, kind: .navigate) { lastAction = "tile Kitchen" }
                            .accessibilityIdentifier("g.layout.\(layout.rawValue).Kitchen")
                        GlassTile(title: "Security System", subtitle: "Armed Home", symbol: "shield", family: .securityHome,
                                  isActive: false, kind: .navigate) { lastAction = "tile Security System" }
                            .accessibilityIdentifier("g.layout.\(layout.rawValue).Security")
                        layoutTile(layout, "Towel Rack", "On", "powerplug", .power, true)
                    }
                    .equalHeightTiles()
                    .tileLayout(layout)
                }
            }
        }
    }

    /// The three frosted proposals beside the shipped solid finish, on the same tiles (``TileFinish``): off, on in a family
    /// colour, lit, dark ink on a bright fill, an error, a room and a long name. Proposals only; the owner picks.
    private var finishes: some View {
        section("Tile Finish") {
            ForEach(TileFinish.allCases.filter { onlyFinish == nil || $0 == onlyFinish }) { finish in
                VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
                    Text(finish.title).font(.headline).accessibilityAddTraits(.isHeader)
                    Text(finish.summary)
                        .font(.footnote)
                        .foregroundStyle(.white)
                    FinishSampleGrid(finish: finish)
                }
            }
        }
    }

    private func layoutTile(_ layout: TileLayout, _ title: String, _ subtitle: String, _ symbol: String,
                            _ family: ColorFamily, _ active: Bool) -> some View {
        GlassTile(title: title, subtitle: subtitle, symbol: symbol, family: family, isActive: active) {
            lastAction = "tile \(title)"
        }
        .accessibilityIdentifier("g.layout.\(layout.rawValue).\(title)")
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

/// The tiles every finish is judged on: off, on in a family colour, lit, bright with dark ink, an error, a room, a long name
/// and a coloured navigation tile, drawn with one ``TileFinish``. On a page they sit on the wallpaper; in a sheet, on the cell.
private struct FinishSampleGrid: View {
    var finish: TileFinish

    var body: some View {
        DynamicGridLayout(minCellWidth: 150, maxColumns: 4, equalRowHeights: true) {
            sample("Office Lamp", "Off", "lamp.desk", .lights, false)
            sample("Table Lamp", "60%", "lamp.table", .lights, true)
            sample("Living Room Purifier", "Auto · 42%", "air.purifier", .air, true)
            sample("Bath Fan", "Off", "fan", .air, false)
            sample("Towel Rack", "On", "powerplug", .power, true)
            sample("Thermostat", "Heating to 68°", "thermometer.medium", .heating, true)
            GlassTile(title: "Garage Door", subtitle: "Didn't Respond", symbol: "door.garage.closed", family: .contact,
                      isActive: false, isError: true)
                .tileIdentifier("g.finish.\(finish.rawValue).Garage Door")
            GlassTile(title: "Kitchen", symbol: "stove", family: .neutral, fillRGB: RoomPalette.fill(forRoom: "kitchen"),
                      isActive: false, kind: .navigate)
                .tileIdentifier("g.finish.\(finish.rawValue).Kitchen")
        }
        .equalHeightTiles()
        .tileFinish(finish)
    }

    private func sample(_ title: String, _ subtitle: String, _ symbol: String, _ family: ColorFamily, _ active: Bool) -> some View {
        GlassTile(title: title, subtitle: subtitle, symbol: symbol, family: family, isActive: active)
            .tileIdentifier("g.finish.\(finish.rawValue).\(title)")
    }
}

/// A sheet with tiles on the sheet surface and the bottom glass section bar. Launch with `FENTON_APPEARANCE=light` to
/// draw it in the light appearance (`SystemAppearance`); the page behind stays dark.
private struct DirectionGGallerySheet: View {
    enum Section: String, CaseIterable, Identifiable {
        case controls = "Controls", families = "Families", finish = "Finish", apps = "Apps", settings = "Settings"
        var id: Self { self }
        var symbol: String {
            switch self {
            case .controls: "appletvremote.gen4"
            case .families: "circle.hexagongrid"
            case .finish: "sparkles.rectangle.stack"
            case .apps: "play.rectangle"
            case .settings: "gearshape"
            }
        }
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
                    case .finish: finishes
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
            .modalTabBar(Section.allCases, label: "TV sections", title: \.rawValue,
                         symbol: { $0.symbol }, selection: $section,
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

    /// The tile finish proposals on the sheet's cells (`-directionGFinish <raw>` limits them to one).
    private var finishes: some View {
        let only = UserDefaults.standard.string(forKey: "directionGFinish").flatMap(TileFinish.init(rawValue:))
        return ForEach(TileFinish.allCases.filter { only == nil || $0 == only }) { finish in
            VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
                Text(finish.title).font(.headline).accessibilityAddTraits(.isHeader)
                FinishSampleGrid(finish: finish)
            }
        }
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
