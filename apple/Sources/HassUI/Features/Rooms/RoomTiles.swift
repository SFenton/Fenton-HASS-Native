import HassCore
import HassDesign
import SwiftUI

// MARK: - Status rail

/// A room's overview chips (web `RoomSectionRail`). A chip opens its card's sheet; a chip without one is inert.
struct RoomStatusRail: View {
    var controller: RoomController
    var onOpen: (RoomCard) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: HassTokens.Spacing.s) {
                ForEach(controller.page.overviewCards) { card in
                    RoomChip(controller: controller, card: card) { onOpen(card) }
                }
            }
            .padding(.horizontal, HassTokens.Spacing.l)
        }
        // Clipped like the Home rail so chips never scroll under the folded Duo's trailing toolbar rail.
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(controller.page.title) status")
    }
}

/// One overview chip.
struct RoomChip: View {
    var controller: RoomController
    var card: RoomCard
    var action: () -> Void

    var body: some View {
        let chip = controller.chip(card)
        let summary = ScreenshotPrivacy.isRedacting && card.kind == .occupancy ? "Hidden" : chip.summary
        StatusChipButton(title: chip.title, summary: summary, symbol: SymbolMap.symbol(for: chip.icon),
                         family: card.kind.tone.family, isActive: chip.isActive, action: chip.opensSheet ? action : nil)
            .accessibilityIdentifier("room.chip.\(card.title)")
    }
}

// MARK: - Cards

/// A room card (web `DefaultRoomSourceCard`): a ``GlassTile`` whose kind follows the card's semantics, drawn in its
/// device's colour family (``RoomTileFace``): dark when off, filled when on, the warm lit tile for lights.
///
/// Device cards (humidifier, wake light, vacuum, dishwasher) draw this generic tile until their lanes replace them in
/// ``RoomCardView``.
struct RoomCardTile: View {
    var controller: RoomController
    var card: RoomCard
    var onOpen: () -> Void
    @Environment(\.householdViewer) private var viewer

    var body: some View {
        let display = controller.display(card, viewer: viewer)
        let face = RoomTileFace.resolve(card, entity: controller.displayEntity(card), display: display,
                                         running: controller.usesAlternate(card))
        GlassTile(
            title: display.title,
            subtitle: display.subtitle,
            symbol: SymbolMap.symbol(for: card.icon),
            family: face.family,
            isActive: face.isActive,
            isUnavailable: card.hasInteraction && !display.isEnabled,
            kind: kind(display.semantics),
            action: activate
        )
        .accessibilityIdentifier("room.card.\(card.title)")
    }

    /// Runs the card's action, or opens its sheet.
    func activate() {
        if controller.tap(card) == .openSheet { onOpen() }
    }

    private func kind(_ semantics: RoomTileSemantics) -> GlassTileKind {
        switch semantics {
        case .modal: .navigate
        case .command: .command
        case .toggle: .toggle
        case let .selection(isSelected): .selection(isSelected: isSelected)
        case .state: .state
        }
    }
}

/// Dispatches a card to its tile (web `RoomSourceCard`). Lanes building device tiles replace their case here.
struct RoomCardView: View {
    var controller: RoomController
    var card: RoomCard
    /// The page's shared controller when this card is a bathroom fan.
    var fan: BathroomFanController?
    var onOpen: () -> Void
    @Environment(HassConnection.self) private var connection: HassConnection?

    var body: some View {
        // Hook points: wake light and dishwasher tiles land here; until then they use the generic tile.
        if card.control == .bathroomFan, let fan {
            BathroomFanRoomTile(fan: fan, card: card, onOpen: onOpen)
        } else if card.control == .garageDoor, let tile = Self.garageTile(card) {
            // The Security page's door control (web `GarageDoorTile`), titled as the room card.
            GarageDoorTile(tile: tile, liveState: controller.store.entity(card.entityId).state?.state,
                           caller: controller.caller, canSend: connection.map { SecurityScreen.canSend($0.status) } ?? true)
                .accessibilityIdentifier("room.card.\(card.title)")
        } else {
            RoomCardTile(controller: controller, card: card, onOpen: onOpen)
        }
    }

    /// The Security garage door tile for a garage card, keeping the card's title and icon.
    static func garageTile(_ card: RoomCard) -> SecurityConfig.Tile? {
        guard var tile = SecurityConfig.controlTiles.first(where: { $0.kind == .garageDoor && $0.entityId == card.entityId })
        else { return nil }
        tile.title = card.title
        return tile
    }
}

// MARK: - App launch

/// Square app tiles from a remote's apps (web `app-launch` sections), sharing the remote sheet's ``AppTile``.
struct RoomAppLaunchGrid: View {
    var remote: MediaRemoteController
    var imageServer: HassServer?
    @ScaledMetric(relativeTo: .subheadline) private var minTileWidth: CGFloat = 110

    var body: some View {
        DynamicGridLayout(minCellWidth: minTileWidth, maxColumns: 6) {
            ForEach(remote.config.apps) { app in
                AppTile(app: app, display: remote.display(app), imageURL: imageServer.flatMap { server in app.imagePath.map(server.url) }) {
                    remote.tap(app)
                }
                .accessibilityIdentifier("room.app.\(app.title)")
            }
        }
    }
}
