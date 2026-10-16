import HassCore
import HassDesign
import SwiftUI

// MARK: - Colors

/// Colors for the away pages, from the web's card colors, checked at 4.5:1 for text.
enum AwayTint {
    /// Vacation Mode on (web `SWITCH_ACTIVE_COLOR` 67,160,71).
    static let vacation = Color(red: 0.26, green: 0.63, blue: 0.28)
    /// Vacation pending confirmation (web `SECURITY_COLOR` 30,136,229).
    static let pending = Color(red: 0.12, green: 0.53, blue: 0.90)
    /// Solo Trip (web `SOLO_TRIP_COLOR` 91,141,239).
    static let soloTrip = Color(red: 0.36, green: 0.55, blue: 0.94)
    /// A checked pre-vacation task: the green the mockups use for done (n5-vacation-mode), deeper on a light sheet.
    static let checked = HassTokens.Ink.success
}

// MARK: - Section

/// A titled block of a page (web `section` + `SectionHeader` + `Description`). Direction G's header: 20 Bold on the
/// wallpaper, and 15 Semibold secondary inside a sheet over its inset list (`.agents/design/direction-g.md`, Type).
/// Vacation opens in the Account and Quick Links sheets, so the sheet style is the usual one.
struct AwaySection<Content: View>: View {
    var title: String?
    var description: String?
    @ViewBuilder var content: Content
    @Environment(\.tileSurface) private var surface

    var body: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
            if let title {
                Group {
                    if surface == .sheet {
                        FormHeader(title)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, HassTokens.Spacing.l)
                    } else {
                        PageSectionHeader(title)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
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

/// The "<Traveler> Away" notice as an ``InfoBox``.
struct SoloTripNoticeBox: View {
    var notice: SoloTripNotice

    var body: some View {
        InfoBox(title: notice.title, message: notice.description, tone: notice.isSuccess ? .success : .neutral)
            .accessibilityIdentifier("soloTrip.notice")
    }
}

/// A full-width action button (web `FieldActionButton`). The prominent one is the screen's ``PrimaryButtonStyle``
/// capsule (`#0071E3`, white label); the rest are bordered in the action tint, or G's red when destructive.
struct AwayActionButton: View {
    var title: String
    var role: ButtonRole?
    var prominent = false
    var identifier: String
    var action: () -> Void

    var body: some View {
        Group {
            if prominent {
                Button(role: role, action: action) { Text(title) }
                    .buttonStyle(PrimaryButtonStyle())
            } else {
                Button(role: role, action: action) {
                    Text(title).frame(maxWidth: .infinity, minHeight: HassTokens.minTarget - 16)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(role == .destructive ? HassTokens.Ink.danger : HassTokens.Ink.action)
            }
        }
        .accessibilityIdentifier(identifier)
    }
}

// MARK: - Date fields

extension ScheduleDateField {
    /// A picker over a ``WallClock``: a date-only picker keeps the time and a time-only picker keeps the date.
    init(_ label: String, _ part: Part, _ value: WallClock, id identifier: String,
         calendar: Calendar = .current, onChange: @escaping (WallClock) -> Void) {
        self.init(label: label, part: part, value: value.date(in: calendar) ?? .now, identifier: identifier) { picked in
            let parts = WallClock(picked, calendar: calendar)
            switch part {
            case .date: onChange(WallClock(date: parts.date, time: value.time))
            case .time: onChange(WallClock(date: value.date, time: parts.time))
            case .dateAndTime: onChange(parts)
            }
        }
    }
}

/// Quiet time before a picker that writes to Home Assistant reports its value.
let liveDateCommitDelay: Duration = .milliseconds(900)
