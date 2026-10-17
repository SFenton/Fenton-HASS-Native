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
                RoomSectionHeader(title: "Controllers")
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
                .hassSheet(.page, height: .full) // Detail pages push inside it
        }
    }
}

/// A controller's card (direction G, n4 sprinklers): a low battery warning above it, then one module holding the
/// controller's row, which opens its sheet, and its battery, next and last watering, and hub status.
struct SprinklerControllerCard: View {
    var controller: SprinklerController
    var open: () -> Void
    private let format = SprinklerFormat()
    @ScaledMetric(relativeTo: .footnote) private var minPillWidth: CGFloat = 150

    var body: some View {
        let snapshot = controller.snapshot
        VStack(alignment: .leading, spacing: HassTokens.Spacing.m) {
            if snapshot.batteryLow, let percent = snapshot.batteryPercent {
                InlineAlert("\(controller.config.title) Battery \(SprinklerFormat.number(percent))%", symbol: "battery.25percent")
            }
            // Dense while the battery pill is orange (direction G, Layers: warm text on the thicker module).
            ModuleList(snapshot.batteryLow ? .dense : .thin) {
                // The row opens the sheet even while the controller is offline: its status lives there.
                SprinklerControllerRow(title: controller.config.title, subtitle: format.subtitle(snapshot),
                                       isWatering: controller.isWatering, action: open)
                    .accessibilityIdentifier("sprinklers.controller.\(controller.id)")
                DynamicGridLayout(minCellWidth: minPillWidth, maxColumns: 2, spacing: 0) {
                    StatusPill(label: "Battery", value: format.battery(snapshot), symbol: "battery.100percent",
                               tone: snapshot.batteryLow ? .warning : .neutral, surface: .module)
                    StatusPill(label: "Next Watering", value: format.nextStart(snapshot), symbol: "calendar.badge.clock", surface: .module)
                    StatusPill(label: "Last Watering", value: format.lastStart(snapshot.lastRun), symbol: "clock.arrow.circlepath",
                               surface: .module)
                    StatusPill(label: "Hub", value: snapshot.hubConnected ? "Connected" : "Unavailable",
                               symbol: "antenna.radiowaves.left.and.right", tone: snapshot.hubConnected ? .ok : .unavailable,
                               surface: .module)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// The controller's row at the top of its card: its glyph, name and status, with a chevron because it opens the
/// controller's sheet. While watering, the glyph and status take the water colour.
struct SprinklerControllerRow: View {
    var title: String
    var subtitle: String
    var isWatering: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ModuleRow(title, subtitle: subtitle, symbol: SprinklerStyle.symbol,
                      glyph: isWatering ? ColorFamily.water.glyph : ColorFamily.water.offGlyph,
                      subtitleInk: isWatering ? ColorFamily.water.glyph : nil, showsChevron: true)
        }
        .buttonStyle(ModuleRowButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(subtitle)
        .accessibilityHint("Opens the controller.")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Shared pieces

enum SprinklerStyle {
    static let symbol = "sprinkler.and.droplets"
    /// The water family's glyph colour (direction G): active zones, chosen days and the controller row.
    static let water = ColorFamily.water.glyph
}
