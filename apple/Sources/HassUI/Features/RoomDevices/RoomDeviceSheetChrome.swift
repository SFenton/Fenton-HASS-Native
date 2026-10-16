import HassCore
import HassDesign
import SwiftUI

/// Colors the device sheets share. Tiles, chips and buttons take their colours from the direction G colour
/// families (`ColorFamily`); these are the dial tints the families do not cover.
enum RoomDeviceStyle {
    /// Humidifier dial and accents: the mockup's water arc (`#30B4DC`; direction G, Colour families: Water).
    static let humidifierTint = DialTint(red: 48, green: 180, blue: 220)
    /// Humidity comfort band, 40–50% (web trail rgba(67, 160, 71)).
    static let comfortTrail = DialTint(red: 67, green: 160, blue: 71, opacity: 0.92)
    /// Condensation risk band, 60–80% (web trail rgba(251, 140, 0)).
    static let highTrail = DialTint(red: 251, green: 140, blue: 0, opacity: 0.9)
}

/// Navigation chrome for a device sheet: title, optional subtitle and Done (pattern: `.agents/patterns/room-device-sheets.md`).
struct RoomDeviceSheetChrome<Content: View>: View {
    var title: String
    var subtitle: String?
    var identifier: String
    var content: () -> Content
    @Environment(\.dismiss) private var dismiss

    init(title: String, subtitle: String? = nil, identifier: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.identifier = identifier
        self.content = content
    }

    var body: some View {
        NavigationStack {
            content()
                .modalChrome()
                .navigationTitle(title)
                .inlineNavigationTitle()
                .sheetSubtitle(subtitle)
                .toolbar {
                    SheetCloseItem(identifier: "device.sheet.done") { dismiss() }
                }
        }
        .accessibilityIdentifier(identifier)
    }
}

/// A titled group of controls (web `SectionHeader` + `DynamicGrid`), under the shared room section header.
struct DeviceSection<Content: View>: View {
    var title: String
    var footnote: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.m) {
            RoomSectionHeader(title: title, inSheet: true)
            if let footnote {
                Text(footnote)
                    .font(.footnote)
                    .foregroundStyle(HassTokens.Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

/// A grid of tiles: 2 columns on a phone, up to 4 where there is room, every tile as tall as the tallest.
struct DeviceTileGrid<Content: View>: View {
    var maxColumns = 4
    @ViewBuilder var content: () -> Content
    @ScaledMetric(relativeTo: .subheadline) private var minTileWidth: CGFloat = 132

    var body: some View {
        DynamicGridLayout(minCellWidth: minTileWidth, maxColumns: maxColumns, equalRowHeights: true) { content() }
            .equalHeightTiles()
    }
}
