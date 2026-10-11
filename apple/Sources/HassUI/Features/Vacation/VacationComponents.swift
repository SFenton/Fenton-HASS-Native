import HassCore
import HassDesign
import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

// MARK: - Colors

/// Colors for the away pages, from the web's card colors, checked at 4.5:1 for text.
enum AwayTint {
    /// Vacation Mode on (web `SWITCH_ACTIVE_COLOR` 67,160,71).
    static let vacation = Color(red: 0.26, green: 0.63, blue: 0.28)
    /// Vacation pending confirmation (web `SECURITY_COLOR` 30,136,229).
    static let pending = Color(red: 0.12, green: 0.53, blue: 0.90)
    /// Solo Trip (web `SOLO_TRIP_COLOR` 91,141,239).
    static let soloTrip = Color(red: 0.36, green: 0.55, blue: 0.94)
    /// Alert text: a red dark enough for 4.5:1 on light materials and light enough on dark ones.
    static let alert = dynamic(light: (0.70, 0.11, 0.11), dark: (1.0, 0.55, 0.52))

    private static func dynamic(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        #if canImport(UIKit)
        Color(uiColor: UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        })
        #else
        Color(nsColor: NSColor(name: nil) { appearance in
            let c = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        })
        #endif
    }
}

// MARK: - Section

/// A titled block of a page (web `section` + `SectionHeader` + `Description`).
struct AwaySection<Content: View>: View {
    var title: String?
    var description: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.m) {
            if let title {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(HassTokens.Ink.primary)
                    .accessibilityAddTraits(.isHeader)
            }
            if let description {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(HassTokens.Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

/// Two sections side by side when the page is wide enough, else stacked (web `ResponsiveSectionGrid`).
struct AwaySectionGrid<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        DynamicGridLayout(minCellWidth: 340, maxColumns: 2, spacing: HassTokens.Spacing.xl) { content }
    }
}

// MARK: - Alerts and notices

/// An inline error (web `InlineAlert`).
struct AwayInlineAlert: View {
    var text: String

    var body: some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.circle.fill").accessibilityHidden(true)
        }
        .font(.subheadline)
        .foregroundStyle(AwayTint.alert)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(text)")
    }
}

/// The "<Traveler> Away" notice as an ``InfoBox``.
struct SoloTripNoticeBox: View {
    var notice: SoloTripNotice

    var body: some View {
        InfoBox(title: notice.title, message: notice.description, tone: notice.isSuccess ? .success : .neutral)
            .accessibilityIdentifier("soloTrip.notice")
    }
}

/// A full-width action button (web `FieldActionButton`).
struct AwayActionButton: View {
    var title: String
    var role: ButtonRole?
    var prominent = false
    var identifier: String
    var action: () -> Void

    var body: some View {
        Group {
            if prominent {
                Button(role: role, action: action) { label }.buttonStyle(.borderedProminent)
            } else {
                Button(role: role, action: action) { label }.buttonStyle(.bordered)
            }
        }
        .controlSize(.large)
        .accessibilityIdentifier(identifier)
    }

    private var label: some View {
        Text(title).frame(maxWidth: .infinity, minHeight: HassTokens.minTarget - 16)
    }
}

// MARK: - Date fields

extension ScheduleDateField {
    /// A picker over one part of a ``WallClock``: changing the date keeps the time and vice versa.
    init(_ label: String, _ part: Part, _ value: WallClock, id identifier: String,
         calendar: Calendar = .current, onChange: @escaping (WallClock) -> Void) {
        self.init(label: label, part: part, value: value.date(in: calendar) ?? .now, identifier: identifier) { picked in
            let parts = WallClock(picked, calendar: calendar)
            onChange(part == .date ? WallClock(date: parts.date, time: value.time) : WallClock(date: value.date, time: parts.time))
        }
    }
}

/// Quiet time before a picker that writes to Home Assistant reports its value.
let liveDateCommitDelay: Duration = .milliseconds(900)
