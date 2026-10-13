import HassCore
import HassDesign
import SwiftUI

// MARK: - Sheet

/// The sheet a room card opens (web `RoomSourceModal`). Media remotes present ``MediaRemoteSheet`` instead (see
/// ``RoomScreen``); everything else draws here inside its own navigation stack with Close.
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
            .modalChrome()
            .navigationTitle(controller.sheetTitle(for: card))
            .inlineNavigationTitle()
            .toolbar { SheetCloseItem { dismiss() } }
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
            groupDetail(.lights, group)
        case let .climate(group):
            groupDetail(.climate, group)
        case let .occupancy(group):
            groupDetail(.occupancy, group)
        case let .contacts(group):
            groupDetail(.contacts, group)
        case .allContacts:
            RoomAllContacts(controller: controller)
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

    /// The shared room detail (Home's overview pages), reading the controller's optimistic state. The sheet's title
    /// names occupancy and contact groups, so those drop their heading (web `hideDirectHeader`).
    private func groupDetail(_ kind: RoomOverviewKind, _ group: RoomGroup) -> some View {
        RoomGroupDetail(kind: kind, group: group, showsHeadings: false, read: controller.entity) { controller.send($0) }
    }
}

// MARK: - Group content

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

/// Every room's doors and windows, each room pushing its sensors (web `ContactSheet` overview with drill-down), for
/// rooms without their own contact group (Back Deck, Garage).
struct RoomAllContacts: View {
    var controller: RoomController
    @State private var selected: RoomGroup?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        RoomOverviewGrid(kind: .contacts) { selected = $0 }
            .navigationDestination(item: $selected) { group in
                RoomGroupDetailPage(kind: .contacts, group: group) { dismiss() }
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
