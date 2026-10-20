import HassCore
import HassDesign
import SwiftUI

// MARK: - Bathroom fan tile

/// The bathroom fan's room tile (web `BathroomFanTile`): opens the fan sheet, with Lock and Power as a trailing rail of
/// round buttons. Both send the fan script's explicit target state (never a toggle) through ``BathroomFanController``.
///
/// Owner design, 2026-10-17 (pattern: `.agents/patterns/entity-tile.md`, Accessory rail):
/// - one short status line: `On`, `Off`, `Off in 12:30` (a live countdown from the deadline helper while the timer
///   runs) or `Unavailable`. The lock is never in the text; its button shows it and VoiceOver speaks it;
/// - the buttons are centred on the tile and clear of the chevron (the shared ``GlassTile`` places the rail), 44 pt
///   circles that stay circles at accessibility sizes, and absent while the fan is unavailable.
struct BathroomFanRoomTile: View {
    @Bindable var fan: BathroomFanController
    var card: RoomCard
    var onOpen: () -> Void

    var body: some View {
        // A one-second clock only while a countdown shows; otherwise it ticks hourly, which keeps the tile's identity
        // (and so its press and layout state) the same either way.
        TimelineView(.periodic(from: .now, by: fan.showsCountdown ? 1 : 3600)) { context in
            tile(at: context.date)
        }
    }

    private func tile(at now: Date) -> some View {
        GlassTile(
            title: card.title,
            subtitle: fan.tileStatusText(at: now),
            symbol: SymbolMap.symbol(for: card.icon),
            family: .air,
            isActive: fan.powerAvailable && fan.powerOn,
            kind: .navigate,
            action: onOpen
        ) {
            if fan.powerAvailable {
                HStack(spacing: HassTokens.Spacing.s) {
                    if fan.lockAvailable {
                        FanRailButton(label: "Lock", symbol: fan.locked ? "lock.fill" : "lock.open", isOn: fan.locked,
                                      tileIsLit: fan.powerOn, id: "room.fan.\(fan.config.powerEntityId).lock") {
                            fan.setLocked(!fan.locked)
                        }
                    }
                    FanRailButton(label: "Power", symbol: "power", isOn: fan.powerOn, tileIsLit: fan.powerOn,
                                  id: "room.fan.\(fan.config.powerEntityId).power") {
                        fan.setPower(!fan.powerOn)
                    }
                }
            }
        }
        .tileIdentifier("room.card.\(card.title)")
        .tileAccessibilityValue(fan.tileSpokenValue(at: now))
        .tileSingleLineSubtitle()
    }
}
