import HassCore
import HassDesign
import SwiftUI

/// The bathroom fan sheet (web `BathroomFanModalContent.tsx`): Power and Lock tiles, and an off timer.
///
/// Owner design, 2026-10-17 (pattern: `.agents/patterns/room-device-sheets.md`): Power is the air (teal) family and Lock
/// the security blue, so the two read apart at a glance. The timer is a row of six lengths and one button that turns
/// the fan off after the chosen time (and on first, if it is off); a running timer is a big orange countdown with a
/// thin progress bar and a Clear Timer button. There is no "Auto-disable lock" choice: the fan always unlocks when
/// its timer ends.
public struct BathroomFanSheet: View {
    @State private var controller: BathroomFanController

    /// Creates the sheet.
    public init(config: BathroomFanConfig, store: EntityStore, caller: any HassServiceCalling) {
        _controller = State(initialValue: BathroomFanController(config: config, store: store, caller: caller))
    }

    /// Creates the sheet on the app's connection.
    public init(config: BathroomFanConfig, connection: HassConnection) {
        self.init(config: config, store: connection.store, caller: connection)
    }

    init(controller: BathroomFanController) {
        _controller = State(initialValue: controller)
    }

    public var body: some View {
        RoomDeviceSheetChrome(title: "\(controller.config.roomTitle) Fan", identifier: "device.sheet.fan") {
            ScrollView {
                BathroomFanControls(controller: controller)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                    .padding(HassTokens.Spacing.l)
            }
        }
    }
}

/// The fan's controls, separate from the chrome so hosted tests render them directly.
struct BathroomFanControls: View {
    @Bindable var controller: BathroomFanController

    /// The idle timer's footnote. True to the fan script: `timer_start` ends with `switch.turn_on`.
    static let timerFootnote = "The fan runs, then turns itself off. Starting a timer turns it on if it's off."

    var body: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.xl) {
            // Power is the fan's air teal; Lock is the security blue (direction G, Colour families), so the two tiles
            // are told apart by colour as well as by glyph and name.
            DeviceTileGrid(maxColumns: 2) {
                GlassTile(title: "Power", subtitle: controller.powerStateText, symbol: "power", family: .air,
                          isActive: controller.powerOn && controller.powerAvailable, isUnavailable: !controller.powerAvailable) {
                    controller.setPower(!controller.powerOn)
                }
                .accessibilityIdentifier("fan.power")
                GlassTile(title: "Lock", subtitle: controller.lockStateText, symbol: controller.locked ? "lock.fill" : "lock.open",
                          family: .securityHome, isActive: controller.locked && controller.lockAvailable,
                          isUnavailable: !controller.lockAvailable) {
                    controller.setLocked(!controller.locked)
                }
                .accessibilityIdentifier("fan.lock")
            }

            DeviceSection(title: "Timer") {
                if controller.timerPending {
                    FanTimerRunning(controller: controller)
                } else {
                    FanTimerPicker(controller: controller)
                }
            }
        }
    }

    /// `4 minutes 5 seconds` for VoiceOver.
    static func spokenRemaining(_ seconds: Int) -> String { BathroomFanController.spokenRemaining(seconds) }
}
