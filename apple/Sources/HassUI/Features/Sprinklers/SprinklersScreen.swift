import HassCore
import HassDesign
import SwiftUI

/// The Sprinklers page (web `SprinklersPage.tsx` + `SprinklerController.tsx`; spec `.agents/pages/sprinklers/spec.md`).
///
/// One card per B-hyve controller (tile and status pills); the tile opens the controller's sheet. Cards sit side
/// by side when the page is wide enough (web `ResponsiveSectionGrid`).
public struct SprinklersScreen: View {
    @State private var controllers: [SprinklerController]
    @State private var open: SprinklerController?
    private let initialDetail: SprinklerDetail?
    @ScaledMetric(relativeTo: .body) private var minCardWidth: CGFloat = 340

    /// Creates the page.
    /// - Parameters:
    ///   - store: Live entity state.
    ///   - caller: Where service calls go (the connection, or a recorder in the gallery and tests).
    ///   - openController: A controller id whose sheet opens at once (gallery and journeys).
    ///   - detail: A detail page to show in that sheet at once.
    public init(store: EntityStore, caller: any HassServiceCalling, openController: String? = nil, detail: SprinklerDetail? = nil) {
        let controllers = SprinklersConfig.controllers.map { SprinklerController(config: $0, store: store, caller: caller) }
        _controllers = State(initialValue: controllers)
        _open = State(initialValue: controllers.first { $0.id == openController })
        initialDetail = detail
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HassTokens.Spacing.m) {
                Text("Controllers")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(HassTokens.Ink.primary)
                    .accessibilityAddTraits(.isHeader)
                DynamicGridLayout(minCellWidth: minCardWidth, maxColumns: 2, spacing: HassTokens.Spacing.xl) {
                    ForEach(controllers) { controller in
                        SprinklerControllerCard(controller: controller) { open = controller }
                    }
                }
            }
            .padding(.horizontal, HassTokens.Spacing.l)
            .padding(.vertical, HassTokens.Spacing.m)
        }
        .scrollTelemetry("Sprinklers")
        .accessibilityIdentifier("sprinklers.scroll")
        .navigationTitle("Sprinklers")
        .sheet(item: $open) { controller in
            SprinklerControllerSheet(controller: controller, initialDetail: initialDetail)
                .galleryLastCallBanner()
                .hassSheet()
        }
    }
}

/// A controller's card: low battery warning, the tile that opens the sheet, and four status pills.
struct SprinklerControllerCard: View {
    var controller: SprinklerController
    var open: () -> Void
    private let format = SprinklerFormat()
    @ScaledMetric(relativeTo: .footnote) private var minPillWidth: CGFloat = 150

    var body: some View {
        let snapshot = controller.snapshot
        VStack(alignment: .leading, spacing: HassTokens.Spacing.m) {
            if snapshot.batteryLow, let percent = snapshot.batteryPercent {
                InlineAlert("Battery \(SprinklerFormat.number(percent))%", symbol: "battery.25percent")
            }
            // The tile opens the sheet even while the controller is offline: its status lives there.
            GlassTile(title: controller.config.title, subtitle: format.subtitle(snapshot), symbol: SprinklerStyle.symbol,
                      tint: SprinklerStyle.water, isActive: controller.isWatering, kind: .navigate, action: open)
                .accessibilityIdentifier("sprinklers.controller.\(controller.id)")
            DynamicGridLayout(minCellWidth: minPillWidth, maxColumns: 4, spacing: HassTokens.Spacing.s) {
                StatusPill(label: "Battery", value: format.battery(snapshot), symbol: "battery.100percent",
                           tone: snapshot.batteryLow ? .warning : .neutral)
                StatusPill(label: "Next watering", value: format.nextStart(snapshot), symbol: "calendar.badge.clock")
                StatusPill(label: "Last watering", value: format.lastStart(snapshot.lastRun), symbol: "clock.arrow.circlepath")
                StatusPill(label: "Hub", value: snapshot.hubConnected ? "Connected" : "Unavailable",
                           symbol: "antenna.radiowaves.left.and.right", tone: snapshot.hubConnected ? .ok : .unavailable)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Shared pieces

enum SprinklerStyle {
    static let symbol = "sprinkler.and.droplets"
    /// Water tint for active zones and the controller tile.
    static let water = HassTokens.Tint.water
}

