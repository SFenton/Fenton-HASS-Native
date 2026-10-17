import HassCore
import HassDesign
import SwiftUI

/// The Climate tab on the app's connection.
struct ClimateScreen: View {
    @Environment(HassConnection.self) private var connection

    var body: some View {
        ClimatePage(controller: ClimateController(store: connection.store, caller: connection))
    }
}

/// What the thermostat sheet opens on: a tab and, optionally, a detail page pushed on it.
struct ClimateSheetRequest: Identifiable, Hashable {
    var tab: ClimateConfig.Tab
    var route: ClimateRoute?
    var id: String { "\(tab.rawValue)-\(String(describing: route))" }
}

/// The Climate page (web `ThermostatPage`, `ha-sfenton-react-dash@9ac2a46:src/pages/DashboardViewPage.tsx:7397`).
/// Spec: `.agents/pages/climate/spec.md`; direction G mockup n3. Whole Home's dial straight on the wallpaper (no card,
/// owner 2026-10-16) with the compact Thermostat Hub pill under it, any notices, open doors and windows, then the three
/// Advanced Controls rows that open the sheet on their tab.
struct ClimatePage: View {
    @State private var controller: ClimateController
    @State private var sheet: ClimateSheetRequest?
    /// Shown above the sheet's content (the gallery's last-call line).
    private let sheetAccessory: AnyView?
    @ScaledMetric(relativeTo: .subheadline) private var minContactWidth: CGFloat = 160

    init(controller: ClimateController, initialSheet: ClimateSheetRequest? = nil, sheetAccessory: AnyView? = nil) {
        _controller = State(initialValue: controller)
        _sheet = State(initialValue: initialSheet)
        self.sheetAccessory = sheetAccessory
    }

    var body: some View {
        let lookup = controller.lookup
        ScrollView {
            VStack(alignment: .leading, spacing: HassTokens.Spacing.xl) {
                wholeHome(lookup)
                let open = ClimateLogic.openContactSensors(lookup)
                if !open.isEmpty {
                    section("Open Contact Sensors") {
                        DynamicGridLayout(minCellWidth: minContactWidth, maxColumns: 4, equalRowHeights: true) {
                            ForEach(open) { sensor in
                                GlassTile(
                                    title: sensor.title,
                                    subtitle: ClimateLogic.contactState(controller.entity(sensor.entityId)),
                                    symbol: ClimateStyle.symbol(sensor.isWindow ? "mdi:window-open" : "mdi:door-open"),
                                    family: .contact,
                                    isActive: true,
                                    kind: .state
                                )
                                .tileIdentifier("climate.contact.\(sensor.entityId)")
                            }
                        }
                        .equalHeightTiles()
                    }
                }
                section("Advanced Controls") {
                    ModuleList {
                        ForEach(ClimateConfig.Tab.allCases) { tab in
                            Button { sheet = ClimateSheetRequest(tab: tab) } label: {
                                ModuleRow(tab.entryTitle, subtitle: tab.description, symbol: ClimateStyle.symbol(tab.icon), showsChevron: true)
                            }
                            .buttonStyle(ModuleRowButtonStyle())
                            .accessibilityLabel(tab.entryTitle)
                            .accessibilityHint(tab.description)
                            .accessibilityIdentifier("climate.entry.\(tab.rawValue)")
                        }
                    }
                }
            }
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, HassTokens.Spacing.l)
            .padding(.vertical, HassTokens.Spacing.m)
        }
        .scrollTelemetry("Climate")
        .accessibilityIdentifier("climate.scroll")
        .navigationTitle("Climate")
        .toolbar {
            ToolbarItem(placement: .primaryAction) { FreshnessIndicator() }
        }
        .sheet(item: $sheet) { request in
            ClimateSheet(controller: controller, request: request)
                // Bottom edge: at the top a wrapped debug line covered the sheet's Back and Close on iPad.
                .safeAreaInset(edge: .bottom) { sheetAccessory }
                .hassSheet(.page)
        }
    }

    /// A titled section on the wallpaper.
    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.s + 2) {
            RoomSectionHeader(title: title)
            content()
        }
    }

    /// Whole Home: the dial on the wallpaper (eco-away thermostat while away, `hvac_action` always from the global
    /// one), the hub pill and the notices.
    @ViewBuilder
    private func wholeHome(_ lookup: EntityLookup) -> some View {
        let dialEntityId = ClimateLogic.wholeHomeDialEntityId(lookup)
        section("Whole Home") {
            VStack(spacing: HassTokens.Spacing.m) {
                ClimateThermostatDial(
                    entityId: dialEntityId,
                    title: "Whole Home",
                    action: ClimateLogic.hvacAction(lookup(ClimateConfig.globalThermostatEntityId)),
                    caller: controller.caller,
                    commitEntityIds: { targets in Self.wholeHomeCommitIds(dialEntityId: dialEntityId, targets: targets) }
                )
                .frame(maxWidth: .infinity)
                // The 270° ring leaves the bottom of its square empty (about 14% of the side); the hub pill tucks
                // into it instead of sitting a ring's width below (owner, 2026-10-16: "takes up too much space").
                .padding(.bottom, -Self.dialBottomOverlap)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("climate.wholeHome")
                ThermostatHubPill(controller: controller)
                if let notice = ClimateLogic.awayNotice(climateEntityId: ClimateConfig.globalThermostatEntityId, useEffectiveMode: true, lookup) {
                    ClimateNotice(text: notice, symbol: "house")
                        .accessibilityIdentifier("climate.awayNotice")
                }
                if ClimateLogic.showsIntegrationWarning(lookup) {
                    ClimateNotice(text: ClimateConfig.Copy.integrationOffWarning, symbol: "exclamationmark.triangle", isWarning: true)
                        .accessibilityIdentifier("climate.integrationWarning")
                }
            }
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
    }

    /// How much of the Whole Home dial's empty bottom the hub pill reclaims.
    static let dialBottomOverlap: CGFloat = 36

    /// The web fans a range set on the global thermostat out to every room (`useCommitThermostatTemperature`);
    /// the eco-away thermostat and single targets go to the dial's own entity.
    static func wholeHomeCommitIds(dialEntityId: String, targets: ThermostatTargets) -> [String] {
        if dialEntityId == ClimateConfig.globalThermostatEntityId, case .range = targets {
            return ClimateConfig.roomClimateEntityIds
        }
        return [dialEntityId]
    }
}
