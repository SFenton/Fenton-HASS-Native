import HassCore
import HassDesign
import SwiftUI

// MARK: - Device sheets

/// A device sheet owned by another lane, presented on its own because it carries its own navigation stack
/// (`.agents/patterns/room-device-sheets.md`, `vacuum-sheet.md`). Cards whose device has no sheet here, or that
/// need the app's connection when there is none (the debug gallery), keep ``RoomCardSheet``'s generic tiles.
enum RoomDeviceModal: Identifiable {
    case vacuum(VacuumConfig)
    /// Shares the room tile's controller, so the tile's accessories and the sheet agree (web
    /// `BathroomFanCommandProvider`).
    case bathroomFan(BathroomFanController, powerEntityId: String)
    case airPurifier(AirPurifierConfig)
    case humidifier(HumidifierConfig)
    case grill

    var id: String {
        switch self {
        case let .vacuum(vacuum): "vacuum.\(vacuum.entityId)"
        case let .bathroomFan(_, powerEntityId): "fan.\(powerEntityId)"
        case let .airPurifier(purifier): "purifier.\(purifier.pm25EntityId)"
        case let .humidifier(humidifier): "humidifier.\(humidifier.powerEntityId)"
        case .grill: "grill"
        }
    }

    /// The sheet for a room device, if one is wired.
    /// - Parameters:
    ///   - device: What the card opens.
    ///   - hasConnection: Whether the app's connection is available (the vacuum and humidifier sheets need it).
    ///   - fan: The page's shared fan controller for a power switch.
    @MainActor
    static func resolve(_ device: RoomDeviceSheet, hasConnection: Bool, fan: (String) -> BathroomFanController?) -> RoomDeviceModal? {
        switch device {
        case let .vacuum(entityId):
            guard hasConnection, let vacuum = Vacuums.all.first(where: { $0.entityId == entityId }) else { return nil }
            return .vacuum(vacuum)
        case let .bathroomFan(powerEntityId):
            return fan(powerEntityId).map { .bathroomFan($0, powerEntityId: powerEntityId) }
        case let .airQuality(pm25EntityId):
            return AirPurifierConfig.forPM25Entity(pm25EntityId).map { .airPurifier($0) }
        case let .humidifier(powerEntityId):
            guard hasConnection else { return nil }
            return HumidifierConfig.forPowerEntity(powerEntityId).map { .humidifier($0) }
        case .grill:
            return .grill
        case .dishwasher, .wakeLight, .bed:
            // Dishwasher and Bedroom alarms lanes: generic tiles until they land.
            return nil
        }
    }
}

/// The sheet for a ``RoomDeviceModal``, in its lane's presentation.
struct RoomDeviceModalSheet: View {
    var modal: RoomDeviceModal
    var store: EntityStore
    var caller: any HassServiceCalling
    var connection: HassConnection?

    var body: some View {
        switch modal {
        case let .vacuum(vacuum):
            if let connection { VacuumSheet(vacuum: vacuum, connection: connection).vacuumPresentation() }
        case let .bathroomFan(fan, _):
            BathroomFanSheet(controller: fan).roomDevicePresentation(.form)
        case let .airPurifier(purifier):
            AirPurifierSheet(config: purifier, store: store, caller: caller).roomDevicePresentation(.form)
        case let .humidifier(humidifier):
            if let connection { HumidifierSheet(config: humidifier, connection: connection).roomDevicePresentation(.page) }
        case .grill:
            GrillSheet(config: .bearGrills, store: store, caller: caller).roomDevicePresentation(.form)
        }
    }
}

// MARK: - Bathroom fan tile

/// The bathroom fan's room tile (web `BathroomFanTile`): opens the fan sheet, with Lock and Power in the trailing
/// accessory. Both send the fan script's explicit target state (never a toggle) through ``BathroomFanController``.
struct BathroomFanRoomTile: View {
    @Bindable var fan: BathroomFanController
    var card: RoomCard
    var onOpen: () -> Void

    var body: some View {
        GlassTile(
            title: card.title,
            subtitle: fan.powerStateText,
            symbol: SymbolMap.symbol(for: card.icon),
            tint: RoomTone.power.color,
            isActive: fan.powerAvailable && fan.powerOn,
            kind: .navigate,
            action: onOpen
        ) {
            HStack(spacing: HassTokens.Spacing.xs) {
                accessory("Lock", symbol: fan.locked ? "lock.fill" : "lock.open", isOn: fan.locked,
                          isAvailable: fan.lockAvailable, id: "lock") { fan.setLocked(!fan.locked) }
                accessory("Power", symbol: "power", isOn: fan.powerOn, isAvailable: fan.powerAvailable, id: "power") {
                    fan.setPower(!fan.powerOn)
                }
            }
        }
        .accessibilityIdentifier("room.card.\(card.title)")
    }

    private func accessory(_ label: String, symbol: String, isOn: Bool, isAvailable: Bool, id: String,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(isOn ? RoomTone.power.color : HassTokens.Ink.secondary)
                .frame(width: HassTokens.minTarget, height: HassTokens.minTarget)
                .background(.thinMaterial, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
        .accessibilityLabel(label)
        .accessibilityValue(isAvailable ? (isOn ? "On" : "Off") : "Unavailable")
        .accessibilityAddTraits(.isToggle)
        .accessibilityIdentifier("room.fan.\(fan.config.powerEntityId).\(id)")
    }
}
