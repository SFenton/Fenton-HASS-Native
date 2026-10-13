#if DEBUG
import HassDesign
import SwiftUI

/// Every dial state the Climate page will need, from fixture values.
struct ThermostatDialGallery: View {
    /// A fixture and its title.
    struct Fixture: Identifiable {
        var id: String
        var name: String
        var configuration: ThermostatDialConfiguration
    }

    static let fixtures: [Fixture] = [
        Fixture(id: "heating", name: "Heating", configuration: .init(
            title: "Living Room", current: 68.5, targets: .single(72), action: "heating")),
        Fixture(id: "range", name: "Heat and cool range", configuration: .init(
            title: "Whole Home", current: 71, targets: .range(low: 68, high: 75), action: "idle")),
        Fixture(id: "cooling", name: "Cooling", configuration: .init(
            title: "Office", current: 76.5, targets: .single(73), action: "cooling")),
        Fixture(id: "off", name: "Off", configuration: .init(
            title: "Guest Room", current: 64, targets: .single(66), action: "off", isOff: true)),
        Fixture(id: "unavailable", name: "Unavailable", configuration: .init(
            title: "Garage", current: nil, targets: nil, action: "unavailable", isUnavailable: true)),
    ]

    @State private var fixtures = Self.fixtures
    @State private var lastCommit = "None"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HassTokens.Spacing.l) {
                Text("Last commit: \(lastCommit)")
                    .font(.footnote)
                    .foregroundStyle(HassTokens.Ink.secondary)
                    .accessibilityIdentifier("gallery.lastCommit")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: HassTokens.Spacing.l)], spacing: HassTokens.Spacing.l) {
                    ForEach($fixtures) { $fixture in
                        VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
                            Text(fixture.name)
                                .font(.headline)
                                .foregroundStyle(HassTokens.Ink.primary)
                                .accessibilityAddTraits(.isHeader)
                            ThermostatDial(fixture.configuration, size: .modal) { targets in
                                // Echo the commit back like Home Assistant would.
                                fixture.configuration.targets = targets
                                lastCommit = "\(fixture.id) \(Self.describe(targets))"
                            }
                        }
                        .padding(HassTokens.Spacing.l)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: HassTokens.Radius.tile, style: .continuous))
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("gallery.thermostat.\(fixture.id)")
                    }
                }
            }
            .padding(HassTokens.Spacing.l)
        }
        .background(Color.blue.opacity(0.08).ignoresSafeArea())
        .navigationTitle("Thermostat Dial")
    }

    /// `single 72.5` or `range 68-75`, for the last-commit line UI tests read.
    static func describe(_ targets: ThermostatTargets) -> String {
        switch targets {
        case let .single(value): "single \(ThermostatDialConfiguration.compact(value))"
        case let .range(low, high): "range \(ThermostatDialConfiguration.compact(low))-\(ThermostatDialConfiguration.compact(high))"
        }
    }
}
#endif
