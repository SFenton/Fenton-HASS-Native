import HassTelemetry
import SwiftUI

/// The invisible element a UI test reads the last line from.
struct LaunchCostProbeElement: View {
    var body: some View {
        Color.clear
            .frame(width: 2, height: 2)
            .allowsHitTesting(false)
            .accessibilityElement()
            .accessibilityLabel(LaunchCostProbe.latest)
            .accessibilityIdentifier("diagnostics.launchcost")
    }
}
