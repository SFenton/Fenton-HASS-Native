import HassCore
import HassDesign
import SwiftUI

// MARK: - Sheet

/// The sheet a room card opens (web `RoomSourceModal`). Media remotes present ``MediaRemoteSheet`` instead (see
/// ``RoomScreen``); everything else draws here inside its own navigation stack with Done.
struct RoomCardSheet: View {
    var controller: RoomController
    var card: RoomCard
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: HassTokens.Spacing.l) {
                    if let subtitle = controller.sheetSubtitle(for: card) {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(HassTokens.Ink.secondary)
                            .accessibilityIdentifier("room.sheet.subtitle")
                    }
                    RoomSheetBody(controller: controller, card: card, content: controller.sheet(for: card))
                }
                .padding(HassTokens.Spacing.l)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle(controller.sheetTitle(for: card))
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .accessibilityIdentifier("room.sheet.\(card.sheet ?? card.title)")
    }
}

/// The sheet's content by kind. Device cases are hook points: each lane replaces its `.device` case with its sheet.
struct RoomSheetBody: View {
    var controller: RoomController
    var card: RoomCard
    var content: RoomSheetContent

    var body: some View {
        switch content {
        case let .lights(group):
            RoomLightsGrid(controller: controller, group: group)
        case let .climate(group):
            RoomClimateGroupView(controller: controller, group: group)
        case let .occupancy(group):
            RoomEntityGrid(title: nil, items: group.items.map { RoomEntityItem($0.title, $0.entityId, icon: "mdi:motion-sensor") },
                           controller: controller, format: RoomFormat.occupancy, isActive: RoomFormat.isOccupied, tone: .presence)
        case let .contacts(group):
            RoomEntityGrid(title: nil, items: group.items.map { RoomEntityItem($0.title, $0.entityId, icon: RoomFormat.isWindow($0) ? "mdi:window-closed" : "mdi:door") },
                           controller: controller, format: RoomFormat.contact, isActive: RoomFormat.isOpen, tone: .contact)
        case .allContacts:
            RoomAllContactsList(controller: controller)
        case let .items(items):
            RoomEntityGrid(title: nil, items: items.map { RoomEntityItem($0.title, $0.entityId, icon: $0.icon) },
                           controller: controller, format: RoomFormat.compact, isActive: RoomFormat.isActive, tone: card.kind.tone)
        case .device:
            // Wired device sheets (bathroom fan, air quality, humidifier, grill, vacuum) open on their own through
            // ``RoomDeviceModal``. This is the fallback: dishwasher, wake light and beds (lanes still open), and the
            // vacuum and humidifier without the app's connection (the debug gallery).
            RoomDeviceFallback(controller: controller, card: card)
        case .mediaRemote, .fallback:
            RoomSheetFallback(card: card)
        }
    }
}

// MARK: - Group content

/// A room's lights: brightness tiles for dimmable lights, power tiles for the rest, explicit on/off (web
/// `RoomLightDetailCards`).
struct RoomLightsGrid: View {
    var controller: RoomController
    var group: RoomGroup
    @Environment(\.householdViewer) private var viewer
    @ScaledMetric(relativeTo: .subheadline) private var minTileWidth: CGFloat = 140

    var body: some View {
        DynamicGridLayout(minCellWidth: minTileWidth, maxColumns: 4) {
            ForEach(group.items) { item in
                LightGroupTile(title: item.title(for: viewer), entityId: item.entityId,
                               state: controller.store.entity(item.entityId).state) { controller.send($0) }
                    .accessibilityIdentifier("room.light.\(item.entityId)")
            }
        }
    }
}

/// Temperature sensors then vents (web `ClimateSheet` direct group).
struct RoomClimateGroupView: View {
    var controller: RoomController
    var group: RoomGroup

    var body: some View {
        let sensors = group.items.filter { !$0.entityId.hasPrefix("cover.") }
        let vents = group.items.filter { $0.entityId.hasPrefix("cover.") }
        VStack(alignment: .leading, spacing: HassTokens.Spacing.l) {
            if !sensors.isEmpty {
                RoomEntityGrid(title: sensors.count == 1 ? "Temperature Sensor" : "Temperature Sensors",
                               items: sensors.map { RoomEntityItem($0.title, $0.entityId, icon: "mdi:thermometer") }, controller: controller,
                               format: RoomFormat.temperature, isActive: { !RoomFormat.isUnavailable($0) }, tone: .climate)
            }
            if !vents.isEmpty {
                RoomEntityGrid(title: vents.count == 1 ? "Vent" : "Vents", items: vents.map { RoomEntityItem($0.title, $0.entityId, icon: "mdi:air-filter") },
                               controller: controller, format: RoomFormat.compact, isActive: RoomFormat.isActive, tone: .climate)
            }
        }
    }
}

/// A grid of read-only entity tiles (web compact `Card`s in group sheets).
struct RoomEntityGrid: View {
    var title: String?
    var items: [RoomEntityItem]
    var controller: RoomController
    var format: (EntityState?) -> String
    var isActive: (EntityState?) -> Bool
    var tone: RoomTone
    @ScaledMetric(relativeTo: .subheadline) private var minTileWidth: CGFloat = 140

    var body: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.m) {
            if let title { RoomSectionHeader(title: title) }
            DynamicGridLayout(minCellWidth: minTileWidth, maxColumns: 4) {
                ForEach(items) { item in
                    let entity = controller.entity(item.entityId)
                    let redact = ScreenshotPrivacy.isRedacting && tone == .presence
                    GlassTile(title: item.title, subtitle: redact ? "Hidden" : format(entity), symbol: SymbolMap.symbol(for: item.icon),
                              tint: tone.color, isActive: !redact && isActive(entity), isUnavailable: RoomFormat.isUnavailable(entity),
                              kind: .state)
                        .accessibilityIdentifier("room.entity.\(item.entityId)")
                }
            }
        }
    }
}

/// Every room's doors and windows, each room pushing its sensors (web `ContactSheet` overview with drill-down).
struct RoomAllContactsList: View {
    var controller: RoomController

    var body: some View {
        VStack(spacing: HassTokens.Spacing.s) {
            ForEach(RoomGroups.allContacts, id: \.room) { group in
                NavigationLink {
                    ScrollView {
                        RoomEntityGrid(title: nil, items: group.items.map { RoomEntityItem($0.title, $0.entityId, icon: RoomFormat.isWindow($0) ? "mdi:window-closed" : "mdi:door") },
                                       controller: controller, format: RoomFormat.contact, isActive: RoomFormat.isOpen, tone: .contact)
                            .padding(HassTokens.Spacing.l)
                    }
                    .navigationTitle(group.room)
                    .inlineNavigationTitle()
                } label: {
                    GlassTile(title: group.room, subtitle: RoomFormat.contactSummary(group) { controller.entity($0) },
                              symbol: SymbolMap.symbol(for: "mdi:door"), tint: RoomTone.contact.color,
                              isActive: group.items.contains { RoomFormat.isOpen(controller.entity($0.entityId)) }, kind: .state)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(group.room)
                .accessibilityValue(RoomFormat.contactSummary(group) { controller.entity($0) })
                .accessibilityIdentifier("room.contacts.\(group.room)")
            }
        }
    }
}

/// One read-only tile in a ``RoomEntityGrid``.
struct RoomEntityItem: Identifiable {
    var title: String
    var entityId: String
    var icon: String
    var id: String { entityId }

    init(_ title: String, _ entityId: String, icon: String) {
        self.title = title
        self.entityId = entityId
        self.icon = icon
    }
}

// MARK: - Fallbacks

/// Generic tiles for a device sheet whose lane has not landed: the card's entities, read-only.
struct RoomDeviceFallback: View {
    var controller: RoomController
    var card: RoomCard

    var body: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.m) {
            RoomEntityGrid(title: nil, items: controller.fallbackEntityIds(for: card).map { id in
                RoomEntityItem(controller.entity(id)?.friendlyName ?? id, id, icon: card.icon)
            }, controller: controller, format: RoomFormat.withUnit, isActive: { !RoomFormat.isUnavailable($0) }, tone: card.kind.tone)
            Text("More controls for this device are coming.")
                .font(.footnote)
                .foregroundStyle(HassTokens.Ink.secondary)
        }
    }
}

/// A card with no interactive controls here (web `RoomSourceFallback`).
struct RoomSheetFallback: View {
    var card: RoomCard

    var body: some View {
        ContentUnavailableView {
            Label(card.title, systemImage: SymbolMap.symbol(for: card.icon))
        } description: {
            Text("This source does not have interactive controls available from this view.")
        }
    }
}
