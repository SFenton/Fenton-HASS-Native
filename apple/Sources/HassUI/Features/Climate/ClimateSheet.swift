import HassCore
import HassDesign
import SwiftUI

/// A detail page pushed inside the thermostat sheet (web `ThermostatModalDetail`).
enum ClimateRoute: Hashable {
    case room(String)
    case predictive
    case eco(ClimateConfig.EcoOption)
    case tracking(ClimateConfig.TrackingPage)

    /// The page title (web `thermostatModalDetailTitle`).
    var title: String {
        switch self {
        case let .room(key): ClimateConfig.room(key: key)?.title ?? "Room"
        case .predictive: "Predictive Comfort"
        case let .eco(option): option.title
        case let .tracking(page): page.title
        }
    }

    /// The tab the route belongs to.
    var tab: ClimateConfig.Tab {
        switch self {
        case .room: .rooms
        case .predictive, .eco: .automation
        case .tracking: .tracking
        }
    }

    /// `room:living_room`, `predictive`, `eco-critical`, `selected-rooms`… (gallery launch argument).
    init?(token: String) {
        if token.hasPrefix("room:") {
            let key = String(token.dropFirst(5))
            guard ClimateConfig.room(key: key) != nil else { return nil }
            self = .room(key)
        } else if token == "predictive" {
            self = .predictive
        } else if let option = ClimateConfig.EcoOption(rawValue: token) {
            self = .eco(option)
        } else if let page = ClimateConfig.TrackingPage(rawValue: token) {
            self = .tracking(page)
        } else {
            return nil
        }
    }
}

/// "Advanced Controls": Rooms, Automation and Tracking tabs with detail pages pushed on a
/// `NavigationStack` (Back returns to the tab, like the web's in-sheet back). Pattern: modal-sheet.
struct ClimateSheet: View {
    var controller: ClimateController
    @State private var tab: ClimateConfig.Tab
    @State private var path: [ClimateRoute]
    @Environment(\.dismiss) private var dismiss

    init(controller: ClimateController, request: ClimateSheetRequest) {
        self.controller = controller
        _tab = State(initialValue: request.route?.tab ?? request.tab)
        _path = State(initialValue: request.route.map { [$0] } ?? [])
    }

    var body: some View {
        NavigationStack(path: $path) {
            ClimateSheetScroll {
                ModalTabBar(tabs: ClimateConfig.Tab.allCases, label: "Thermostat sections", title: \.title,
                            selection: $tab, identifier: "climate.sheet.tabs")
                switch tab {
                case .rooms: ClimateRoomsTab(controller: controller) { path.append($0) }
                case .automation: ClimateAutomationTab(controller: controller) { path.append($0) }
                case .tracking: ClimateTrackingTab(controller: controller) { path.append($0) }
                }
            }
            .accessibilityIdentifier("climate.sheet.\(tab.rawValue)")
            .modalChrome()
            .climateSheetTitle(ClimateConfig.sheetTitle)
            .toolbar { closeButton }
            .navigationDestination(for: ClimateRoute.self) { route in
                ClimateSheetScroll { detail(route) }
                    .accessibilityIdentifier("climate.detail")
                    .modalChrome()
                    .climateSheetTitle(route.title)
                    .toolbar { closeButton }
            }
        }
        .environment(controller.store)
    }

    private var closeButton: some ToolbarContent {
        SheetCloseItem { dismiss() }
    }

    @ViewBuilder
    private func detail(_ route: ClimateRoute) -> some View {
        switch route {
        case let .room(key):
            if let room = ClimateConfig.room(key: key) { ClimateRoomDetail(controller: controller, room: room) }
        case .predictive: PredictiveComfortDetail(controller: controller)
        case let .eco(option): EcoOptionDetail(controller: controller, option: option)
        case let .tracking(page): TrackingRoomsDetail(controller: controller, page: page)
        }
    }
}

extension View {
    /// The sheet's title as a wrapping heading at the top of the content instead of an inline bar title, which
    /// truncated "Advanced Controls" and "Eco Mode Critical Tracking" beside Back and Done on iPhone
    /// and can't grow with Dynamic Type. `navigationTitle` still names the page for Back and VoiceOver.
    /// HIG: Navigation bars, Typography (Dynamic Type).
    @ViewBuilder
    func climateSheetTitle(_ title: String) -> some View {
        #if os(iOS)
        if #available(iOS 18, *) {
            navigationTitle(title)
                .inlineNavigationTitle()
                .toolbar(removing: .title)
                .safeAreaInset(edge: .top, spacing: 0) { ClimateSheetHeading(title: title) }
        } else {
            navigationTitle(title).inlineNavigationTitle()
        }
        #else
        navigationTitle(title)
        #endif
    }
}


/// The page heading ``View/climateSheetTitle(_:)`` draws.
struct ClimateSheetHeading: View {
    var title: String

    var body: some View {
        Text(title)
            .font(.title3.weight(.bold))
            .foregroundStyle(HassTokens.Ink.primary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, HassTokens.Spacing.l)
            .padding(.vertical, HassTokens.Spacing.s)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("climate.sheetHeading")
    }
}

/// The sheet's scrolling column, capped at a readable width on iPad (HIG: Layout).
struct ClimateSheetScroll<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HassTokens.Spacing.xl) { content }
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
                .padding(HassTokens.Spacing.l)
        }
    }
}

// MARK: - Rooms

/// Every room: temperature, occupancy and a disclosure to its detail (web `ThermostatRoomsRoot`).
struct ClimateRoomsTab: View {
    var controller: ClimateController
    var open: (ClimateRoute) -> Void
    @ScaledMetric(relativeTo: .subheadline) private var minTileWidth: CGFloat = 150

    var body: some View {
        let lookup = controller.lookup
        ClimateSection(title: "Rooms", description: ClimateConfig.Tab.rooms.description) {
            DynamicGridLayout(minCellWidth: minTileWidth, maxColumns: 2) {
                ForEach(ClimateConfig.rooms) { room in
                    let occupied = ClimateLogic.isOccupied(lookup(room.occupancyEntityId))
                    GlassTile(
                        title: room.title,
                        subtitle: ClimateLogic.roomSubtitle(room, lookup),
                        symbol: ClimateStyle.symbol(occupied ? "mdi:thermometer-check" : "mdi:thermometer-off"),
                        tint: ClimateStyle.control,
                        isActive: occupied,
                        kind: .navigate
                    ) { open(.room(room.key)) }
                    .accessibilityIdentifier("climate.room.\(room.key)")
                }
            }
        }
    }
}

/// A room's dial, vents and away notice (web `ThermostatRoomModalContent`).
struct ClimateRoomDetail: View {
    var controller: ClimateController
    var room: ClimateConfig.Room
    @ScaledMetric(relativeTo: .subheadline) private var minTileWidth: CGFloat = 140

    var body: some View {
        ClimateThermostatDial(entityId: room.climateEntityId, title: room.title, size: .modal, caller: controller.caller)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("climate.roomDial")
        ClimateSection(title: room.ventSectionTitle) {
            DynamicGridLayout(minCellWidth: minTileWidth, maxColumns: 3) {
                ForEach(Array(room.ventEntityIds.enumerated()), id: \.element) { index, ventId in
                    let vent = controller.entity(ventId)
                    RemoteGlassTile(
                        title: room.ventTitle(at: index),
                        subtitle: ClimateLogic.ventState(vent),
                        symbol: ClimateStyle.symbol("mdi:fan"),
                        tint: ClimateStyle.ventOpen,
                        isActive: vent?.state == "open",
                        isDisabled: vent?.isUnavailable ?? true,
                        semantics: .state
                    ) {}
                    .accessibilityIdentifier("climate.vent.\(ventId)")
                }
            }
        }
        if let notice = ClimateLogic.awayNotice(climateEntityId: room.climateEntityId, useEffectiveMode: false, controller.lookup) {
            ClimateNotice(text: notice, symbol: "house")
                .accessibilityIdentifier("climate.roomAwayNotice")
        }
    }
}

// MARK: - Automation

/// Automatic Thermostat, Eco Mode and Predictive Comfort (web `ThermostatAutomationRoot`).
struct ClimateAutomationTab: View {
    var controller: ClimateController
    var open: (ClimateRoute) -> Void

    var body: some View {
        ClimateSection(title: "Automatic Thermostat") {
            ClimateControlGroup(description: ClimateConfig.Copy.integration) {
                ClimateToggleTile(controller: controller, entityId: ClimateConfig.integrationEntityId, title: "Automatic Thermostat", icon: "mdi:thermostat")
            }
        }
        ClimateSection(title: "Eco Mode") {
            ClimateControlGroup(description: ClimateConfig.Copy.ecoMode) {
                ClimateToggleTile(controller: controller, entityId: ClimateConfig.ecoModeEntityId, title: "Eco Mode", icon: "mdi:leaf")
            }
            ForEach(ClimateConfig.EcoOption.allCases) { option in
                let options = ClimateLogic.selectOptions(controller.entity(option.entityId))
                ClimateControlGroup(description: option.openerDescription) {
                    ClimateOpenerTile(
                        title: option.title,
                        subtitle: ClimateLogic.selectOption(controller.shown(option.entityId) ?? ""),
                        icon: option.icon,
                        isDisabled: options.isEmpty
                    ) { open(.eco(option)) }
                    .accessibilityIdentifier("climate.eco.\(option.rawValue)")
                }
            }
        }
        ClimateSection(title: "Predictive Comfort") {
            ClimateControlGroup(description: ClimateConfig.Copy.predictiveComfort) {
                PredictiveComfortTile(controller: controller) { open(.predictive) }
            }
        }
    }
}

/// Off: tap turns Predictive Comfort on. On: tap opens its detail and a trailing power button turns it off
/// (web `PredictiveComfortSetting`).
struct PredictiveComfortTile: View {
    var controller: ClimateController
    var open: () -> Void

    var body: some View {
        let id = ClimateConfig.predictiveComfortEntityId
        let isOn = controller.isOn(id)
        let disabled = controller.isUnavailable(id)
        let subtitle = ClimateLogic.predictiveSubtitle(controller.lookup, shownState: controller.shown(id))
        let symbol = ClimateStyle.symbol("mdi:home-thermometer-outline")
        if isOn {
            HStack(spacing: HassTokens.Spacing.s) {
                GlassTile(title: "Predictive Comfort", subtitle: subtitle, symbol: symbol, tint: ClimateStyle.control,
                          isActive: true, isUnavailable: disabled, kind: .navigate, action: open)
                    .accessibilityHint("Opens Predictive Comfort controls.")
                    .accessibilityIdentifier("climate.predictive")
                Button { controller.setSwitch(id, on: false) } label: {
                    Image(systemName: "power")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(HassTokens.Ink.primary)
                        .frame(width: HassTokens.minTarget + 8, height: HassTokens.minTarget + 8)
                        .background(.regularMaterial, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(disabled)
                .accessibilityLabel("Turn off Predictive Comfort")
                .accessibilityIdentifier("climate.predictive.power")
            }
        } else {
            GlassTile(title: "Predictive Comfort", subtitle: subtitle, symbol: symbol, tint: ClimateStyle.control,
                      isActive: false, isUnavailable: disabled, kind: .toggle) { controller.setSwitch(id, on: true) }
                .disabled(disabled)
                .accessibilityIdentifier("climate.predictive")
        }
    }
}

/// Predictive Comfort's switches, Current Prediction metrics and reasons (web `PredictiveComfortModalContent`).
struct PredictiveComfortDetail: View {
    var controller: ClimateController
    @ScaledMetric(relativeTo: .subheadline) private var minControlWidth: CGFloat = 240
    @ScaledMetric(relativeTo: .subheadline) private var minMetricWidth: CGFloat = 130

    var body: some View {
        let sensor = controller.entity(ClimateConfig.predictiveSensorEntityId)
        // The web shows the recommendation as the sheet subtitle.
        Text("Recommendation: \(ClimateLogic.predictiveState(ClimateLogic.predictiveRecommendation(controller.lookup)))")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(HassTokens.Ink.secondary)
            .accessibilityIdentifier("climate.predictive.recommendation")
        ClimateSection(title: "Controls") {
            DynamicGridLayout(minCellWidth: minControlWidth, maxColumns: 3) {
                ClimateControlGroup(description: ClimateConfig.Copy.predictiveAutoAdjust) {
                    ClimateToggleTile(controller: controller, entityId: ClimateConfig.predictiveAutoAdjustEntityId, title: "Auto Setpoint Adjustments", icon: "mdi:thermostat-auto")
                }
                ClimateControlGroup(description: ClimateConfig.Copy.predictiveHvacModeChanges) {
                    ClimateToggleTile(controller: controller, entityId: ClimateConfig.predictiveHvacModeChangesEntityId, title: "HVAC Mode Changes", icon: "mdi:hvac")
                }
                ClimateControlGroup(description: ClimateConfig.Copy.predictiveAllowAway) {
                    ClimateToggleTile(controller: controller, entityId: ClimateConfig.predictiveAllowAwayEntityId, title: "Predictive Comfort While Away", icon: "mdi:home-export-outline")
                }
            }
        }
        ClimateSection(title: "Current Prediction") {
            DynamicGridLayout(minCellWidth: minMetricWidth, maxColumns: 3) {
                ForEach(ClimateLogic.predictiveMetrics(sensor)) { metric in
                    VStack(alignment: .leading, spacing: HassTokens.Spacing.xs) {
                        Text(metric.label)
                            .font(.footnote)
                            .foregroundStyle(HassTokens.Ink.secondary)
                        Text(metric.value)
                            .font(.headline)
                            .foregroundStyle(HassTokens.Ink.primary)
                            .monospacedDigit()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(HassTokens.Spacing.m)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: HassTokens.Radius.chip, style: .continuous))
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("climate.metric.\(metric.label)")
                }
            }
            VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
                Text("Why this prediction?")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HassTokens.Ink.primary)
                    .accessibilityAddTraits(.isHeader)
                ForEach(ClimateLogic.predictiveReasonBullets(sensor), id: \.self) { bullet in
                    HStack(alignment: .firstTextBaseline, spacing: HassTokens.Spacing.s) {
                        Text("•").accessibilityHidden(true)
                        Text(bullet).fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.subheadline)
                    .foregroundStyle(HassTokens.Ink.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(HassTokens.Spacing.m)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: HassTokens.Radius.chip, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("climate.predictive.reasons")
        }
    }
}

/// An Eco Mode select's choices, each with its description (web `ThermostatOptionDetailPage`).
struct EcoOptionDetail: View {
    var controller: ClimateController
    var option: ClimateConfig.EcoOption

    var body: some View {
        let options = ClimateLogic.selectOptions(controller.entity(option.entityId))
        if options.isEmpty {
            ClimateNotice(text: option.unavailableMessage, symbol: "exclamationmark.triangle")
        } else {
            ClimateDescription(text: option.pageDescription)
            VStack(alignment: .leading, spacing: HassTokens.Spacing.l) {
                ForEach(options) { choice in
                    let isSelected = controller.shown(option.entityId) == choice.value
                    VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
                        if let description = choice.description { ClimateDescription(text: description) }
                        RemoteGlassTile(
                            title: choice.label, subtitle: nil, symbol: ClimateStyle.symbol(choice.icon ?? option.icon),
                            tint: ClimateStyle.control, isActive: isSelected, isDisabled: false,
                            semantics: .selection(isSelected: isSelected)
                        ) { controller.select(option.entityId, option: choice.value) }
                        .accessibilityIdentifier("climate.option.\(choice.value)")
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(option.title) options")
        }
    }
}

// MARK: - Tracking

/// Track Selected Rooms and the three room-rule openers (web `ThermostatTrackingRoot`).
struct ClimateTrackingTab: View {
    var controller: ClimateController
    var open: (ClimateRoute) -> Void

    var body: some View {
        let summary = controller.trackingSummary
        ClimateSection(title: "Room Tracking", description: ClimateConfig.Tab.tracking.description) {
            ClimateControlGroup(description: ClimateConfig.Copy.trackSelected) {
                ClimateToggleTile(controller: controller, entityId: ClimateConfig.trackSelectedEntityId, title: "Track Selected Rooms", icon: "mdi:home-thermometer")
            }
        }
        ClimateSection(title: "Room Rules") {
            ForEach(ClimateConfig.TrackingPage.allCases) { page in
                ClimateControlGroup(description: page.openerDescription) {
                    ClimateOpenerTile(title: page.title, subtitle: summary.subtitle(page), icon: page.icon,
                                      isDisabled: !summary.isEnabled(page)) { open(.tracking(page)) }
                        .accessibilityIdentifier("climate.tracking.\(page.rawValue)")
                }
            }
        }
    }
}

/// A two-column checkbox grid of one room switch per room (web `ThermostatTrackingDetailPage`).
struct TrackingRoomsDetail: View {
    var controller: ClimateController
    var page: ClimateConfig.TrackingPage
    @ScaledMetric(relativeTo: .subheadline) private var minTileWidth: CGFloat = 150

    var body: some View {
        let summary = controller.trackingSummary
        if !summary.isEnabled(page) {
            ClimateNotice(
                text: page == .selectedRooms ? ClimateConfig.Copy.selectedRoomsDisabled : ClimateConfig.Copy.criticalDisabled,
                symbol: "exclamationmark.triangle")
        } else {
            ClimateDescription(text: page.pageDescription)
            DynamicGridLayout(minCellWidth: minTileWidth, maxColumns: 2) {
                ForEach(ClimateLogic.rooms(for: page, state: controller.shown)) { room in
                    let id = page.entityId(for: room)
                    let isOn = controller.isOn(id)
                    RemoteGlassTile(
                        title: room.title, subtitle: nil, symbol: isOn ? "checkmark.circle.fill" : "circle",
                        tint: ClimateStyle.control, isActive: isOn, isDisabled: controller.isUnavailable(id),
                        semantics: .toggle(isOn: isOn)
                    ) { controller.toggle(id) }
                    .accessibilityIdentifier("climate.track.\(page.rawValue).\(room.key)")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(page.title) rooms")
        }
    }
}
