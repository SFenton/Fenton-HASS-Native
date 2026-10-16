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

/// "Advanced Controls": Rooms, Automation and Tracking tabs with detail pages pushed on a `NavigationStack` (Back
/// returns to the tab, like the web's in-sheet back). Direction G: dark system forms (the sheet's ground and cells)
/// with the tabs on a glass segmented control at the bottom. Pattern: modal-sheet.
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
            Group {
                switch tab {
                case .rooms: ClimateRoomsTab(controller: controller) { path.append(.room($0)) }
                case .automation: ClimateAutomationTab(controller: controller)
                case .tracking: ClimateTrackingTab(controller: controller)
                }
            }
            .accessibilityIdentifier("climate.sheet.\(tab.rawValue)")
            .modalChrome()
            .modalTabBar(ClimateConfig.Tab.allCases, label: "Thermostat sections", title: \.title,
                         selection: $tab, identifier: "climate.sheet.tabs")
            .navigationTitle(ClimateConfig.sheetTitle)
            .inlineNavigationTitle()
            .toolbar { closeButton }
            .navigationDestination(for: ClimateRoute.self) { route in
                detail(route)
                    .accessibilityIdentifier("climate.detail")
                    .modalChrome()
                    .navigationTitle(route.title)
                    .inlineNavigationTitle()
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

// MARK: - Form pieces

/// The sheet's form, capped at a readable width on iPad (HIG: Layout).
struct ClimateForm<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        Form { content }
            .formStyle(.grouped)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
    }
}

/// A row's glyph and title, with an optional second line (a state, or what the row opens).
struct ClimateRowLabel: View {
    var title: String
    var subtitle: String?
    var icon: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(HassTokens.Ink.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(HassTokens.Surface.secondaryInSheet)
                        .monospacedDigit()
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: ClimateStyle.symbol(icon))
                .foregroundStyle(HassTokens.Surface.secondaryInSheet)
                .accessibilityHidden(true)
        }
    }
}

/// A switch or input_boolean as a system switch, sending `homeassistant.toggle` (web `ThermostatToggleSetting`).
/// What it does goes under it in the section footer, and VoiceOver reads it as the hint.
struct ClimateToggleRow: View {
    var controller: ClimateController
    var entityId: String
    var title: String
    var icon: String
    var detail: String?

    var body: some View {
        Toggle(isOn: Binding(get: { controller.isOn(entityId) }, set: { _ in controller.toggle(entityId) })) {
            ClimateRowLabel(title: title, icon: icon)
        }
        .disabled(controller.isUnavailable(entityId))
        .accessibilityLabel(title)
        .accessibilityHint(detail ?? "")
        .accessibilityIdentifier("climate.toggle.\(entityId)")
    }
}

/// A section's toggle with its description as the footer.
struct ClimateToggleSection: View {
    var controller: ClimateController
    var entityId: String
    var title: String
    var icon: String
    var detail: String
    var header: String?

    var body: some View {
        Section {
            ClimateToggleRow(controller: controller, entityId: entityId, title: title, icon: icon, detail: detail)
        } header: {
            if let header { FormHeader(header) }
        } footer: {
            FormFooter(detail)
        }
    }
}

// MARK: - Rooms

/// Every room as a colour tile like the Rooms grid (``RoomPalette``; owner, 2026-10-16: "standardise on room tiles across
/// the app"): the room's glyph, its name, and its temperature and occupancy under it. A tap opens the room's detail
/// (web `ThermostatRoomsRoot`).
struct ClimateRoomsTab: View {
    var controller: ClimateController
    /// Opens a room's detail page by its key (`living_room`).
    var onOpen: (String) -> Void = { _ in }
    @ScaledMetric(relativeTo: .subheadline) private var minTileWidth: CGFloat = 150

    var body: some View {
        let lookup = controller.lookup
        ScrollView {
            VStack(alignment: .leading, spacing: HassTokens.Spacing.l) {
                DynamicGridLayout(minCellWidth: minTileWidth, maxColumns: 4, equalRowHeights: true) {
                    ForEach(ClimateConfig.rooms) { room in
                        GlassTile(
                            title: room.title,
                            subtitle: ClimateLogic.roomSubtitle(room, lookup),
                            symbol: SymbolMap.symbol(for: RoomNavigation.item(for: room.key.replacingOccurrences(of: "_", with: "-"))?.icon ?? "mdi:home-thermometer"),
                            family: .neutral,
                            fillRGB: RoomPalette.fill(forKey: room.key),
                            isActive: false,
                            kind: .navigate
                        ) { onOpen(room.key) }
                        // On the tile's own button, so the identifier, label and value stay on one element.
                        .tileIdentifier("climate.room.\(room.key)")
                    }
                }
                .equalHeightTiles()
                FormFooter(ClimateConfig.Tab.rooms.description)
                    .font(.footnote)
            }
            .padding(HassTokens.Spacing.l)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
    }
}

/// A room's dial, vents and away notice (web `ThermostatRoomModalContent`). The vents are Vents-family tiles that fill
/// while open and show their position.
struct ClimateRoomDetail: View {
    var controller: ClimateController
    var room: ClimateConfig.Room
    @ScaledMetric(relativeTo: .subheadline) private var minTileWidth: CGFloat = 150

    var body: some View {
        ClimateForm {
            Section {
                ClimateThermostatDial(entityId: room.climateEntityId, title: room.title, size: .modal, caller: controller.caller)
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("climate.roomDial")
            }
            .listRowBackground(Color.clear)
            if let notice = ClimateLogic.awayNotice(climateEntityId: room.climateEntityId, useEffectiveMode: false, controller.lookup) {
                Section {
                    Label(notice, systemImage: "house")
                        .foregroundStyle(HassTokens.Ink.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("climate.roomAwayNotice")
                }
            }
            Section {
                DynamicGridLayout(minCellWidth: minTileWidth, maxColumns: 4, equalRowHeights: true) {
                    ForEach(Array(room.ventEntityIds.enumerated()), id: \.element) { index, ventId in
                        let vent = controller.entity(ventId)
                        GlassTile(
                            title: room.ventTitle(at: index),
                            subtitle: ClimateLogic.ventSubtitle(vent),
                            symbol: ClimateStyle.symbol("mdi:fan"),
                            family: .vents,
                            isActive: ClimateLogic.isVentOpen(vent),
                            isUnavailable: vent?.isUnavailable ?? true,
                            kind: .state
                        )
                        .tileIdentifier("climate.vent.\(ventId)")
                    }
                }
                .equalHeightTiles()
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } header: {
                FormHeader(room.ventSectionTitle)
            }
        }
    }
}

// MARK: - Automation

/// Automatic Thermostat, Eco Mode and Predictive Comfort (web `ThermostatAutomationRoot`).
struct ClimateAutomationTab: View {
    var controller: ClimateController

    var body: some View {
        let predictiveId = ClimateConfig.predictiveComfortEntityId
        let predictiveOn = controller.isOn(predictiveId)
        let predictive = ClimateLogic.predictiveSubtitle(controller.lookup, shownState: controller.shown(predictiveId))
        ClimateForm {
            ClimateToggleSection(controller: controller, entityId: ClimateConfig.integrationEntityId,
                                 title: "Automatic Thermostat", icon: "mdi:thermostat", detail: ClimateConfig.Copy.integration)
            Section {
                ClimateToggleRow(controller: controller, entityId: ClimateConfig.ecoModeEntityId, title: "Eco Mode",
                                 icon: "mdi:leaf", detail: ClimateConfig.Copy.ecoMode)
                ForEach(ClimateConfig.EcoOption.allCases) { option in
                    let options = ClimateLogic.selectOptions(controller.entity(option.entityId))
                    let value = ClimateLogic.selectOption(controller.shown(option.entityId) ?? "")
                    NavigationLink(value: ClimateRoute.eco(option)) {
                        LabeledContent {
                            Text(value).foregroundStyle(HassTokens.Surface.secondaryInSheet)
                        } label: {
                            ClimateRowLabel(title: option.title, icon: option.icon)
                        }
                    }
                    .disabled(options.isEmpty)
                    .accessibilityLabel(option.title)
                    .accessibilityValue(value)
                    .accessibilityHint(option.openerDescription)
                    .accessibilityIdentifier("climate.eco.\(option.rawValue)")
                }
            } header: {
                FormHeader("Eco Mode")
            } footer: {
                FormFooter(ClimateConfig.Copy.ecoMode)
            }
            Section {
                Toggle(isOn: Binding(get: { predictiveOn }, set: { controller.setSwitch(predictiveId, on: $0) })) {
                    ClimateRowLabel(title: "Predictive Comfort", subtitle: predictive, icon: "mdi:home-thermometer-outline")
                }
                .disabled(controller.isUnavailable(predictiveId))
                // The switch reads on or off itself; the label keeps the recommendation ("On · Pre-Cool").
                .accessibilityLabel("Predictive Comfort, \(predictive)")
                .accessibilityHint(ClimateConfig.Copy.predictiveComfort)
                .accessibilityIdentifier("climate.predictive")
                if predictiveOn {
                    NavigationLink(value: ClimateRoute.predictive) {
                        Text("Current Prediction").foregroundStyle(HassTokens.Ink.primary)
                    }
                    .accessibilityHint("Opens Predictive Comfort controls.")
                    .accessibilityIdentifier("climate.predictive.open")
                }
            } header: {
                FormHeader("Predictive Comfort")
            } footer: {
                FormFooter(ClimateConfig.Copy.predictiveComfort)
            }
        }
    }
}

/// Predictive Comfort's switches, Current Prediction metrics and reasons (web `PredictiveComfortModalContent`).
struct PredictiveComfortDetail: View {
    var controller: ClimateController

    var body: some View {
        let sensor = controller.entity(ClimateConfig.predictiveSensorEntityId)
        let bullets = ClimateLogic.predictiveReasonBullets(sensor)
        ClimateForm {
            Section {
                // The web shows the recommendation as the sheet subtitle.
                Text("Recommendation: \(ClimateLogic.predictiveState(ClimateLogic.predictiveRecommendation(controller.lookup)))")
                    .font(.headline)
                    .foregroundStyle(HassTokens.Ink.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("climate.predictive.recommendation")
            }
            Section {
                ClimateToggleRow(controller: controller, entityId: ClimateConfig.predictiveAutoAdjustEntityId,
                                 title: "Auto Setpoint Adjustments", icon: "mdi:thermostat-auto",
                                 detail: ClimateConfig.Copy.predictiveAutoAdjust)
                ClimateToggleRow(controller: controller, entityId: ClimateConfig.predictiveHvacModeChangesEntityId,
                                 title: "HVAC Mode Changes", icon: "mdi:hvac",
                                 detail: ClimateConfig.Copy.predictiveHvacModeChanges)
                ClimateToggleRow(controller: controller, entityId: ClimateConfig.predictiveAllowAwayEntityId,
                                 title: "Predictive Comfort While Away", icon: "mdi:home-export-outline",
                                 detail: ClimateConfig.Copy.predictiveAllowAway)
            } header: {
                FormHeader("Controls")
            }
            Section {
                ForEach(ClimateLogic.predictiveMetrics(sensor)) { metric in
                    LabeledContent {
                        Text(metric.value)
                            .foregroundStyle(HassTokens.Ink.primary)
                            .monospacedDigit()
                            .fixedSize(horizontal: false, vertical: true)
                    } label: {
                        Text(metric.label).foregroundStyle(HassTokens.Ink.primary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("climate.metric.\(metric.label)")
                }
            } header: {
                FormHeader("Current Prediction")
            }
            if !bullets.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
                        ForEach(bullets, id: \.self) { bullet in
                            Text(bullet)
                                .foregroundStyle(HassTokens.Ink.primary)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("climate.predictive.reasons")
                } header: {
                    FormHeader("Why This Prediction")
                }
            }
        }
    }
}

/// An Eco Mode select's choices, each with its description, the current one checked (web
/// `ThermostatOptionDetailPage`). HIG: Lists (a checkmark marks the single choice).
struct EcoOptionDetail: View {
    var controller: ClimateController
    var option: ClimateConfig.EcoOption

    var body: some View {
        let options = ClimateLogic.selectOptions(controller.entity(option.entityId))
        ClimateForm {
            if options.isEmpty {
                Section { InlineAlert(option.unavailableMessage) }
                    .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(options) { choice in
                        let isSelected = controller.shown(option.entityId) == choice.value
                        Button {
                            controller.select(option.entityId, option: choice.value)
                        } label: {
                            HStack(spacing: HassTokens.Spacing.m) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(choice.label).foregroundStyle(HassTokens.Ink.primary)
                                    if let description = choice.description {
                                        Text(description)
                                            .font(.footnote)
                                            .foregroundStyle(HassTokens.Surface.secondaryInSheet)
                                    }
                                }
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(HassTokens.Ink.action)
                                    .opacity(isSelected ? 1 : 0)
                                    .accessibilityHidden(true)
                            }
                            .contentShape(Rectangle())
                        }
                        // Reads the choice and what it does ("Use Eco Away Targets, Use the wider away…").
                        .accessibilityLabel([choice.label, choice.description].compactMap { $0 }.joined(separator: ", "))
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                        .accessibilityIdentifier("climate.option.\(choice.value)")
                    }
                } footer: {
                    FormFooter(option.pageDescription)
                }
            }
        }
    }
}

// MARK: - Tracking

/// Track Selected Rooms and the three room-rule openers, each with what it does under it
/// (web `ThermostatTrackingRoot`).
struct ClimateTrackingTab: View {
    var controller: ClimateController

    var body: some View {
        let summary = controller.trackingSummary
        ClimateForm {
            ClimateToggleSection(controller: controller, entityId: ClimateConfig.trackSelectedEntityId,
                                 title: "Track Selected Rooms", icon: "mdi:home-thermometer",
                                 detail: ClimateConfig.Copy.trackSelected, header: "Room Tracking")
            ForEach(ClimateConfig.TrackingPage.allCases) { page in
                Section {
                    NavigationLink(value: ClimateRoute.tracking(page)) {
                        ClimateRowLabel(title: page.title, subtitle: summary.subtitle(page), icon: page.icon)
                    }
                    // Disabled, not unavailable: VoiceOver reads the subtitle ("Enable Track Selected Rooms first")
                    // and "dimmed".
                    .disabled(!summary.isEnabled(page))
                    .accessibilityLabel(page.title)
                    .accessibilityValue(summary.subtitle(page))
                    .accessibilityIdentifier("climate.tracking.\(page.rawValue)")
                } header: {
                    if page == ClimateConfig.TrackingPage.allCases.first { FormHeader("Room Rules") }
                } footer: {
                    FormFooter(page.openerDescription)
                }
            }
        }
    }
}

/// One room switch per room, checked while on (web `ThermostatTrackingDetailPage`).
struct TrackingRoomsDetail: View {
    var controller: ClimateController
    var page: ClimateConfig.TrackingPage

    var body: some View {
        let summary = controller.trackingSummary
        ClimateForm {
            if !summary.isEnabled(page) {
                Section {
                    InlineAlert(page == .selectedRooms ? ClimateConfig.Copy.selectedRoomsDisabled : ClimateConfig.Copy.criticalDisabled)
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(ClimateLogic.rooms(for: page, state: controller.shown)) { room in
                        let id = page.entityId(for: room)
                        let isOn = controller.isOn(id)
                        Button {
                            controller.toggle(id)
                        } label: {
                            HStack(spacing: HassTokens.Spacing.m) {
                                Text(room.title)
                                    .foregroundStyle(HassTokens.Ink.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(isOn ? HassTokens.Ink.action : HassTokens.Surface.secondaryInSheet)
                                    .opacity(controller.isUnavailable(id) ? 0.5 : 1)
                                    .accessibilityHidden(true)
                            }
                            .contentShape(Rectangle())
                        }
                        .disabled(controller.isUnavailable(id))
                        .accessibilityLabel(room.title)
                        .accessibilityValue(isOn ? "On" : "Off")
                        .accessibilityAddTraits(isOn ? .isSelected : [])
                        .accessibilityIdentifier("climate.track.\(page.rawValue).\(room.key)")
                    }
                } footer: {
                    FormFooter(page.pageDescription)
                }
            }
        }
    }
}
