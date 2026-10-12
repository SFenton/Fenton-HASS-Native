import HassCore
import HassDesign
import SwiftUI

/// The bathroom fan sheet (web `BathroomFanModalContent.tsx`): power and automation-lock toggles, an off timer,
/// and while locked, whether the timer also releases the lock.
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

    var body: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.xl) {
            DeviceTileGrid(maxColumns: 2) {
                RemoteGlassTile(title: "Power", subtitle: controller.powerStateText, symbol: "power",
                                tint: HassTokens.Tint.presence, isActive: controller.powerOn && controller.powerAvailable,
                                isDisabled: !controller.powerAvailable, semantics: .toggle(isOn: controller.powerOn)) {
                    controller.setPower(!controller.powerOn)
                }
                .accessibilityIdentifier("fan.power")
                RemoteGlassTile(title: "Lock", subtitle: controller.lockStateText, symbol: controller.locked ? "lock.fill" : "lock.open",
                                tint: HassTokens.Tint.security, isActive: controller.locked && controller.lockAvailable,
                                isDisabled: !controller.lockAvailable, semantics: .toggle(isOn: controller.locked)) {
                    controller.setLocked(!controller.locked)
                }
                .accessibilityIdentifier("fan.lock")
            }

            DeviceSection(title: "Timer") {
                if controller.timerPending {
                    pendingTimer
                } else {
                    timerPicker
                }
                if controller.showsAutoUnlock {
                    Toggle("Auto-disable lock", isOn: Binding(get: { controller.displayedAutoUnlock },
                                                              set: { controller.setAutoUnlock($0) }))
                        .font(.body)
                        .foregroundStyle(HassTokens.Ink.primary)
                        .disabled(!controller.autoUnlockAvailable)
                        .frame(minHeight: HassTokens.minTarget)
                        .accessibilityIdentifier("fan.autoUnlock")
                }
            }
        }
    }

    /// Duration menu and Set (web `SelectActionField`).
    private var timerPicker: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: HassTokens.Spacing.m) { durationMenu; Spacer(minLength: 0); setButton }
            VStack(alignment: .leading, spacing: HassTokens.Spacing.m) { durationMenu; setButton }
        }
    }

    private var durationMenu: some View {
        Picker("Timer length", selection: $controller.selectedMinutes) {
            ForEach(BathroomFanController.timerMinutes, id: \.self) { minutes in
                Text(BathroomFanController.durationTitle(minutes)).tag(minutes)
            }
        }
        .pickerStyle(.menu)
        .frame(minHeight: HassTokens.minTarget)
        .accessibilityIdentifier("fan.timerLength")
    }

    private var setButton: some View {
        Button("Set") { controller.startTimer() }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!controller.canStartTimer)
            .accessibilityLabel("Set timer")
            .accessibilityIdentifier("fan.setTimer")
    }

    /// Remaining time and Clear (web `TimerRow`), counting down each second.
    private var pendingTimer: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = controller.remainingSeconds(at: context.date)
            let text = remaining.map(BathroomFanController.formatRemaining) ?? "Unavailable"
            HStack(spacing: HassTokens.Spacing.m) {
                Label {
                    Text(text).font(.title3.weight(.semibold)).monospacedDigit()
                } icon: {
                    Image(systemName: "timer")
                }
                .foregroundStyle(HassTokens.Ink.primary)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Timer")
                .accessibilityValue(remaining.map(Self.spokenRemaining) ?? "Unavailable")
                .accessibilityIdentifier("fan.remaining")
                Spacer(minLength: 0)
                Button("Clear", role: .destructive) { controller.cancelTimer() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(!controller.timerAvailable)
                    .accessibilityLabel("Clear timer")
                    .accessibilityIdentifier("fan.clearTimer")
            }
        }
    }

    /// `4 minutes 5 seconds` for VoiceOver.
    static func spokenRemaining(_ seconds: Int) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = [.hour, .minute, .second]
        return formatter.string(from: TimeInterval(seconds)) ?? BathroomFanController.formatRemaining(seconds)
    }
}
