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
/// Spec: `.agents/pages/climate/spec.md`. Always full width; the advanced controls open in a sheet.
struct ClimatePage: View {
    @State private var controller: ClimateController
    @State private var sheet: ClimateSheetRequest?
    /// Shown above the sheet's content (the gallery's last-call line).
    private let sheetAccessory: AnyView?
    @ScaledMetric(relativeTo: .subheadline) private var minEntryWidth: CGFloat = 240
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
                if ClimateLogic.showsIntegrationWarning(lookup) {
                    ClimateNotice(text: ClimateConfig.Copy.integrationOffWarning, symbol: "exclamationmark.triangle", tint: ClimateStyle.heat)
                        .accessibilityIdentifier("climate.integrationWarning")
                }
                let open = ClimateLogic.openContactSensors(lookup)
                if !open.isEmpty {
                    ClimateSection(title: "Open Contact Sensors") {
                        DynamicGridLayout(minCellWidth: minContactWidth, maxColumns: 4) {
                            ForEach(open) { sensor in
                                RemoteGlassTile(
                                    title: sensor.title,
                                    subtitle: ClimateLogic.contactState(controller.entity(sensor.entityId)),
                                    symbol: ClimateStyle.symbol(sensor.isWindow ? "mdi:window-open" : "mdi:door-open"),
                                    tint: ClimateStyle.contact, isActive: true, isDisabled: false, semantics: .state
                                ) {}
                                .accessibilityIdentifier("climate.contact.\(sensor.entityId)")
                            }
                        }
                    }
                }
                DynamicGridLayout(minCellWidth: minEntryWidth, maxColumns: 3, spacing: HassTokens.Spacing.l) {
                    ForEach(ClimateConfig.Tab.allCases) { tab in
                        ClimateSection(title: tab.entryTitle, description: tab.description) {
                            ClimateOpenerTile(title: tab.entryTitle, icon: tab.icon) { sheet = ClimateSheetRequest(tab: tab) }
                                .accessibilityIdentifier("climate.entry.\(tab.rawValue)")
                        }
                    }
                }
            }
            .padding(.horizontal, HassTokens.Spacing.l)
            .padding(.vertical, HassTokens.Spacing.m)
        }
        .accessibilityIdentifier("climate.scroll")
        .navigationTitle("Climate")
        .toolbar {
            ToolbarItem(placement: .primaryAction) { FreshnessIndicator() }
        }
        .sheet(item: $sheet) { request in
            ClimateSheet(controller: controller, request: request)
                // Bottom edge: at the top a wrapped debug line covered the sheet's Back and Done on iPad.
                .safeAreaInset(edge: .bottom) { sheetAccessory }
                .climateSheetSizing()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    /// Whole Home: the dial (eco-away thermostat while away, `hvac_action` always from the global one), the hub
    /// pill and the away notice.
    @ViewBuilder
    private func wholeHome(_ lookup: EntityLookup) -> some View {
        let dialEntityId = ClimateLogic.wholeHomeDialEntityId(lookup)
        ClimateSection(title: "Whole Home") {
            ClimateThermostatDial(
                entityId: dialEntityId,
                title: "Whole Home",
                action: ClimateLogic.hvacAction(lookup(ClimateConfig.globalThermostatEntityId)),
                caller: controller.caller,
                commitEntityIds: { targets in Self.wholeHomeCommitIds(dialEntityId: dialEntityId, targets: targets) }
            )
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("climate.wholeHome")
            VStack(spacing: HassTokens.Spacing.m) {
                ThermostatHubPill(controller: controller)
                if let notice = ClimateLogic.awayNotice(climateEntityId: ClimateConfig.globalThermostatEntityId, useEffectiveMode: true, lookup) {
                    ClimateNotice(text: notice, symbol: "house")
                        .accessibilityIdentifier("climate.awayNotice")
                }
            }
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
    }

    /// The web fans a range set on the global thermostat out to every room (`useCommitThermostatTemperature`);
    /// the eco-away thermostat and single targets go to the dial's own entity.
    static func wholeHomeCommitIds(dialEntityId: String, targets: ThermostatTargets) -> [String] {
        if dialEntityId == ClimateConfig.globalThermostatEntityId, case .range = targets {
            return ClimateConfig.roomClimateEntityIds
        }
        return [dialEntityId]
    }
}
