import HassCore
import HassDesign
import SwiftUI

/// Colors the device sheets share, from the web's card tones.
enum RoomDeviceStyle {
    /// Humidifier dial and accents (web `HUMIDIFIER_DIAL_COLOR`, rgba(48, 190, 151)).
    static let humidifierTint = DialTint(red: 48, green: 190, blue: 151)
    /// Selected mode tiles (web rgba(0, 150, 136)).
    static let mode = Color(red: 0, green: 150 / 255, blue: 136 / 255)
    /// Grill cards (web `GRILL_COLOR`).
    static let grill = Color(red: 206 / 255, green: 114 / 255, blue: 38 / 255)
    /// "Turn On" fill: a deep teal that keeps white text above 4.5:1.
    static let powerOn = Color(red: 0, green: 0.43, blue: 0.39)
    /// "Turn Off" fill: a deep red that keeps white text above 4.5:1.
    static let powerOff = Color(red: 0.72, green: 0.15, blue: 0.15)
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
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        VStack(spacing: 0) {
                            Text(title).font(.headline).foregroundStyle(HassTokens.Ink.primary)
                            if let subtitle {
                                Text(subtitle).font(.caption).foregroundStyle(HassTokens.Ink.secondary).monospacedDigit()
                            }
                        }
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("device.sheet.title")
                    }
                    SheetCloseItem(identifier: "device.sheet.done") { dismiss() }
                }
        }
        .accessibilityIdentifier(identifier)
    }
}

/// A titled group of tiles (web `SectionHeader` + `DynamicGrid`).
struct DeviceSection<Content: View>: View {
    var title: String
    var footnote: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.m) {
            RemoteSectionHeader(title: title)
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

/// A grid of choice tiles: 2 columns on a phone, up to 4 where there is room.
struct DeviceTileGrid<Content: View>: View {
    var maxColumns = 4
    @ViewBuilder var content: () -> Content
    @ScaledMetric(relativeTo: .subheadline) private var minTileWidth: CGFloat = 132

    var body: some View {
        DynamicGridLayout(minCellWidth: minTileWidth, maxColumns: maxColumns) { content() }
    }
}

/// A warning or error line (web `InlineAlert`).
struct DeviceAlert: View {
    var text: String
    var symbol = "exclamationmark.triangle.fill"

    var body: some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).foregroundStyle(.orange)
        }
        .font(.subheadline)
        .foregroundStyle(HassTokens.Ink.primary)
        .padding(HassTokens.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: HassTokens.Radius.chip, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Presentation

/// How large a device sheet is on iPad.
public enum RoomDeviceSheetSize: Sendable {
    /// A form-size sheet (fan, purifier, grill).
    case form
    /// A page-size sheet with room for two columns (humidifier).
    case page
}

public extension View {
    /// Presents a device sheet: full height with the drag indicator (content below a medium detent fails the
    /// audit), form or page size on iPad.
    func roomDevicePresentation(_ size: RoomDeviceSheetSize = .form) -> some View {
        modifier(RoomDevicePresentation(size: size))
    }
}

private struct RoomDevicePresentation: ViewModifier {
    var size: RoomDeviceSheetSize

    func body(content: Content) -> some View {
        let sheet = content
            .hassSheet()
        if #available(iOS 18.0, macOS 15.0, *) {
            switch size {
            case .form: sheet.presentationSizing(.form)
            case .page: sheet.presentationSizing(.page)
            }
        } else {
            sheet
        }
    }
}
