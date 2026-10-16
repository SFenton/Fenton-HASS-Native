import HassCore
import HassDesign
import SwiftUI

// MARK: - Pages

/// The household Settings topics ported in this lane, in the web's order (`portedDashboard.ts`
/// `SETTINGS_PAGE_ITEMS`; copy from `settings.json` `items.*`). Raw values match the topic ids of the
/// Settings navigation shell, so `settings.topic.<id>` identifies the row everywhere.
enum HouseholdSettingsPage: String, CaseIterable, Identifiable, Hashable, Sendable {
    case admin, specialDeviceModes, guests, machE

    var id: String { rawValue }

    /// The Settings row title.
    var rowTitle: String {
        switch self {
        case .admin: "Admin Controls"
        case .specialDeviceModes: "Special Device Modes"
        case .guests: "Guest Controls"
        case .machE: "Mach-E"
        }
    }

    /// The Settings row subtitle.
    var subtitle: String {
        switch self {
        case .admin: "Presence-Based Toggles, Automation Overrides, and More"
        case .specialDeviceModes: "Allows enabling special device modes, such as High AQI Mode."
        case .guests: "Toggle automations when guests stay over."
        case .machE: "Controls for the Mustang Mach-E."
        }
    }

    /// The page's navigation title (web route titles: Admin, Special Device Modes, Guest Controls, Mach-E).
    var pageTitle: String {
        switch self {
        case .admin: HouseholdSettingsConfig.Admin.pageTitle
        case .specialDeviceModes: HouseholdSettingsConfig.SpecialDeviceModes.pageTitle
        case .guests: HouseholdSettingsConfig.Guests.pageTitle
        case .machE: HouseholdSettingsConfig.MachE.pageTitle
        }
    }

    /// The row's SF Symbol (web `mdi:shield-account`, `mdi:tune-vertical`, `mdi:account-multiple`, `mdi:car-estate`).
    var symbol: String {
        switch self {
        case .admin: "person.badge.shield.checkmark"
        case .specialDeviceModes: "slider.vertical.3"
        case .guests: "person.2"
        case .machE: "car.side"
        }
    }
}

// MARK: - Destination

/// A household page wired to the signed-in connection.
struct HouseholdSettingsDestination: View {
    var page: HouseholdSettingsPage
    @Environment(EntityStore.self) private var store
    @Environment(HassConnection.self) private var connection

    var body: some View {
        HouseholdSettingsPageView(page: page, store: store, caller: connection)
    }
}

/// A household page on any store and service caller (the connection, or the gallery's recorder).
struct HouseholdSettingsPageView: View {
    var page: HouseholdSettingsPage
    @State private var controller: HouseholdSettingsController

    /// Creates the page.
    init(page: HouseholdSettingsPage, store: EntityStore, caller: any HassServiceCalling) {
        self.page = page
        _controller = State(initialValue: HouseholdSettingsController(store: store, caller: caller))
    }

    /// Creates the page on an existing controller (tests).
    init(page: HouseholdSettingsPage, controller: HouseholdSettingsController) {
        self.page = page
        _controller = State(initialValue: controller)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HassTokens.Spacing.xl) {
                switch page {
                case .admin: AdminSettingsContent(controller: controller)
                case .specialDeviceModes: SpecialDeviceModesContent(controller: controller)
                case .guests: GuestControlsContent(controller: controller)
                case .machE: MachEContent(controller: controller)
                }
            }
            .padding()
            // Readable width on iPad and the unfolded Duo (HIG: Layout, readable content guides).
            .frame(maxWidth: 840)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(page.pageTitle)
        .scrollTelemetry("Settings · \(page.rawValue)")
        .accessibilityIdentifier("household.\(page.rawValue)")
    }
}

// MARK: - Shared pieces

extension HassTokens.Tint {
    /// Toggle tiles' active tint (web `SWITCH_ACTIVE_COLOR`, 67/160/71).
    static let settingsSwitch = Color(red: 67 / 255, green: 160 / 255, blue: 71 / 255)
    /// Read-only control tiles (web `CONTROL_COLOR`, 75/126/210).
    static let settingsControl = Color(red: 75 / 255, green: 126 / 255, blue: 210 / 255)
}

extension PresenceOverrideState {
    /// The web card color.
    var tint: Color { Color(red: Double(rgb.red) / 255, green: Double(rgb.green) / 255, blue: Double(rgb.blue) / 255) }
}

/// The grid household tiles sit in; columns narrow with Dynamic Type instead of clipping titles.
struct HouseholdTileGrid<Content: View>: View {
    /// Narrowest tile before the grid drops a column.
    var minWidth: CGFloat = 200
    var maxColumns = 6
    @ViewBuilder var content: Content
    @ScaledMetric(relativeTo: .subheadline) private var scale: CGFloat = 1

    var body: some View {
        DynamicGridLayout(minCellWidth: minWidth * scale, maxColumns: maxColumns) { content }
    }
}

/// An on/off tile for one entity, driven by the controller.
struct HouseholdToggleTile: View {
    var tile: HouseholdSettingsConfig.Tile
    var controller: HouseholdSettingsController

    var body: some View {
        let display = controller.toggle(tile.entityId)
        GlassTile(
            title: tile.title,
            subtitle: tile.showsState ? display.subtitle : nil,
            symbol: SymbolMap.symbol(for: tile.icon),
            tint: HassTokens.Tint.settingsSwitch,
            isActive: display.isOn,
            isUnavailable: display.isUnavailable,
            kind: .toggle
        ) {
            controller.flip(tile.entityId)
        }
        .accessibilityIdentifier("household.tile.\(tile.entityId)")
    }
}

// MARK: - Special Device Modes

/// Special Device Modes (web `SpecialDeviceModesPage`): the High AQI Mode toggle.
struct SpecialDeviceModesContent: View {
    var controller: HouseholdSettingsController

    var body: some View {
        let config = HouseholdSettingsConfig.SpecialDeviceModes.self
        SettingsSection(title: config.highAqi.title, paragraphs: config.highAqi.paragraphs) {
            HouseholdTileGrid(minWidth: 240, maxColumns: 2) {
                HouseholdToggleTile(tile: config.highAqiTile, controller: controller)
            }
        }
    }
}

// MARK: - Guest Controls

/// Guest Controls (web `GuestControlsPage`): one toggle per guest room.
struct GuestControlsContent: View {
    var controller: HouseholdSettingsController

    var body: some View {
        let config = HouseholdSettingsConfig.Guests.self
        SettingsSection(title: config.section.title, paragraphs: config.section.paragraphs) {
            // Web: two columns, up to three, cells at most 320 px; the app keeps growing (four or more on iPad).
            HouseholdTileGrid(minWidth: 150, maxColumns: 6) {
                ForEach(config.tiles) { HouseholdToggleTile(tile: $0, controller: controller) }
            }
        }
    }
}

// MARK: - Mach-E

/// Mach-E (web `ControlPage` for `mach-e`): read-only state tiles.
struct MachEContent: View {
    var controller: HouseholdSettingsController

    var body: some View {
        let config = HouseholdSettingsConfig.MachE.self
        VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
            Text(config.sectionTitle)
                .font(.title3.weight(.semibold))
                .foregroundStyle(HassTokens.Ink.primary)
                .accessibilityAddTraits(.isHeader)
            HouseholdTileGrid(minWidth: 150, maxColumns: 4) {
                ForEach(config.tiles) { tile in
                    let display = controller.readOnly(tile)
                    GlassStateTile(
                        title: tile.title,
                        subtitle: display.subtitle,
                        symbol: SymbolMap.symbol(for: tile.icon),
                        tint: HassTokens.Tint.settingsControl,
                        isActive: display.isActive,
                        isUnavailable: display.isUnavailable
                    )
                    .accessibilityIdentifier("household.tile.\(tile.entityId)")
                }
            }
        }
    }
}

// MARK: - Read-only tile

/// An entity tile that only shows state (web `EntityActionCard` with no action): the ``GlassTile`` face with
/// hit testing and the button trait removed. Feature-local until the shared read-only tile lands in HassDesign
/// (the Room pages lane owns `GlassTile`); switch to it then.
struct GlassStateTile: View {
    var title: String
    var subtitle: String?
    var symbol: String
    var tint: Color
    var isActive: Bool
    var isUnavailable = false

    var body: some View {
        GlassTile(title: title, subtitle: subtitle, symbol: symbol, tint: tint, isActive: isActive,
                  isUnavailable: isUnavailable, kind: .command) {}
            .allowsHitTesting(false)
            .accessibilityRemoveTraits(.isButton)
    }
}
