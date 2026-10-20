import HassCore
import HassDesign
import SwiftUI

/// The idle timer: six lengths, one primary button, one footnote.
struct FanTimerPicker: View {
    @Bindable var controller: BathroomFanController

    var body: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.m) {
            FanTimerLengthRow(selection: $controller.selectedMinutes)
            Button(BathroomFanController.startButtonTitle(controller.selectedMinutes), action: start)
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!controller.canStartTimer)
                .accessibilityIdentifier("fan.setTimer")
            Text(BathroomFanControls.timerFootnote)
                .font(.footnote)
                .foregroundStyle(HassTokens.Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func start() { controller.startTimer() }
}
