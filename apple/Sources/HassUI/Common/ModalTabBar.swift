import HassDesign
import SwiftUI

// MARK: - Modal tab bar

/// The one section switcher for a tabbed modal (media remote, thermostat advanced controls, vacuum; pattern:
/// `.agents/patterns/modal-sheet.md`).
///
/// Direction G (`.agents/design/direction-g.md`, Sheets) draws it as a system segmented control on a glass
/// capsule, pinned along the bottom of the modal like the web's `ModalIconTabNav`
/// (``SwiftUI/View/modalTabBar(_:label:title:symbol:selection:identifier:placement:)``). It stays a segmented
/// control, not a tab bar: HIG Segmented controls (iOS, iPadOS): "Consider it for switching between closely related
/// subviews; use a tab bar for completely separate app sections". The glass marks it as a navigation-layer
/// control floating over the content (HIG: Materials, Liquid Glass).
///
/// On iPhone (compact width) the segments are the web's icons (`ModalIconTabNav`; owner, 2026-10-16: "show icons like the
/// web app instead of text titles"), which fit five sections where titles do not; on iPad and the unfolded Duo (regular
/// width) they are text titles. HIG Segmented controls: "Prefer text or images, not a mix, in one control" and "Limit
/// segments: ... about 5 on iPhone". Icon segments still carry their titles for VoiceOver. At accessibility text sizes,
/// where segments cannot grow, the control becomes a menu of text titles that names the selected section.
/// A caller that passes no `symbol` always shows text. The glass is Liquid Glass on iOS 26 (`glassEffect`, a navigation
/// control: HIG Materials) and a thin-material capsule before (``SwiftUI/View/navigationGlass(in:)``).
struct ModalTabBar<Item: Hashable & Identifiable>: View {
    var tabs: [Item]
    /// Spoken name of the control, e.g. `Thermostat sections`.
    var label: String
    var title: (Item) -> String
    /// SF Symbol per tab; nil shows text segments.
    var symbol: ((Item) -> String)?
    /// The count each tab badges (0 for none); nil for a bar with no badges.
    var badge: ((Item) -> Int)?
    @Binding var selection: Item
    var identifier: String
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let form = ModalTabBarStyle.form(hasSymbols: symbol != nil, hasBadges: badge != nil, compactWidth: sizeClass == .compact,
                                         accessibilitySize: typeSize.isAccessibilitySize)
        if form == .menu {
            // Titles, not icons: at accessibility sizes the section names are what a reader needs (owner, 2026-10-16:
            // "keep text labels ... at accessibility sizes where the existing menu fallback applies").
            Picker(label, selection: $selection) {
                ForEach(tabs) { tab in
                    let count = badge?(tab) ?? 0
                    // The count follows the name, as the web's tab does for a screen reader.
                    Text(count > 0 ? "\(title(tab)), \(count)" : title(tab))
                        .accessibilityLabel(ModalTabBarStyle.accessibilityTitle(title(tab), badge: count))
                        .tag(tab)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, minHeight: HassTokens.minTarget, alignment: .leading)
            .accessibilityIdentifier(identifier)
            // The same glass as the segmented bar, so content scrolling under the bottom bar stays behind it.
            .padding(.horizontal, HassTokens.Spacing.m)
            .navigationGlass(in: Capsule())
        } else if form == .badged || form == .badgedWithTitles {
            // A system segmented control draws a title or an image, never a badge, and VoiceOver cannot be given a count
            // for one segment, so a bar with badges draws its own segments on the same glass capsule.
            BadgedTabSegments(tabs: tabs, title: title, symbol: symbol, badge: badge ?? { _ in 0 },
                              showsTitles: form == .badgedWithTitles, selection: $selection, identifier: identifier, label: label)
                .padding(ModalTabBarStyle.glassInset)
                .navigationGlass(in: Capsule())
        } else {
            Picker(label, selection: $selection) {
                ForEach(tabs) { tab in
                    if form == .icons, let symbol {
                        // A label, not a bare image: the segmented control reads its title to VoiceOver.
                        Label(title(tab), systemImage: symbol(tab))
                            .labelStyle(.iconOnly)
                            .tag(tab)
                    } else {
                        Text(title(tab)).tag(tab)
                    }
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.large)
            .accessibilityIdentifier(identifier)
            .padding(ModalTabBarStyle.glassInset)
            .navigationGlass(in: Capsule())
        }
    }
}

/// Where ``SwiftUI/View/modalTabBar(_:label:title:symbol:selection:identifier:placement:)`` pins the control.
enum ModalTabBarPlacement: Sendable {
    /// Under the header.
    case top
    /// Along the bottom edge, floating over the content on glass (direction G; the default).
    case bottom
}

/// Measurements and the form of the glass section bar.
enum ModalTabBarStyle {
    /// Glass visible around the segmented control.
    static let glassInset: CGFloat = 4

    /// How the control draws its sections.
    enum Form: Equatable {
        /// A segmented control of icons (iPhone), each named for VoiceOver.
        case icons
        /// A segmented control of text titles (iPad, unfolded Duo, or no icons supplied).
        case text
        /// A menu naming the selected section (accessibility text sizes, where segments cannot grow).
        case menu
        /// Our own segments of icons with count badges (iPhone, folded Duo).
        case badged
        /// Our own segments of an icon over its title, with count badges (iPad, unfolded Duo).
        case badgedWithTitles
    }

    /// The form for the environment.
    /// - Parameters:
    ///   - hasSymbols: The caller supplied an SF Symbol per section.
    ///   - hasBadges: The caller supplied a count per section, which the system's segmented control cannot draw.
    ///   - compactWidth: Compact horizontal size class (iPhone, folded Duo).
    ///   - accessibilitySize: An accessibility Dynamic Type size.
    static func form(hasSymbols: Bool, hasBadges: Bool = false, compactWidth: Bool, accessibilitySize: Bool) -> Form {
        if accessibilitySize { return .menu }
        if hasBadges { return hasSymbols && compactWidth ? .badged : .badgedWithTitles }
        return hasSymbols && compactWidth ? .icons : .text
    }

    /// A badge as drawn: capped at "9+" like the header's Profile badge; nil for none.
    static func badgeText(_ count: Int) -> String? {
        guard count > 0 else { return nil }
        return count > 9 ? "9+" : "\(count)"
    }

    /// What VoiceOver says for a section: its title, then the count ("Overdue Chores, 3 items").
    static func accessibilityTitle(_ title: String, badge: Int) -> String {
        guard badge > 0 else { return title }
        return "\(title), \(badge) \(badge == 1 ? "item" : "items")"
    }

    /// Height of a badged segment showing an icon alone, and one with its title under the icon (HIG: 44 pt targets).
    static let iconSegmentHeight: CGFloat = 44
    static let titledSegmentHeight: CGFloat = 56
}

extension View {
    /// Pins a ``ModalTabBar`` to this modal page, along the bottom edge by default (direction G). Apply it after
    /// ``modalChrome()`` so the content fades out under the tab bar as well as the title.
    ///
    /// - Parameter badge: A count per section, drawn on its icon and spoken with its name ("Overdue Chores, 3 items"). A bar
    ///   with badges draws its own segments (``ModalTabBarStyle/Form/badged``); one without keeps the system control.
    func modalTabBar<Item: Hashable & Identifiable>(
        _ tabs: [Item], label: String, title: @escaping (Item) -> String, symbol: ((Item) -> String)? = nil,
        badge: ((Item) -> Int)? = nil,
        selection: Binding<Item>, identifier: String, placement: ModalTabBarPlacement = .bottom
    ) -> some View {
        safeAreaInset(edge: placement == .top ? .top : .bottom, spacing: 0) {
            ModalTabBar(tabs: tabs, label: label, title: title, symbol: symbol, badge: badge, selection: selection, identifier: identifier)
                .padding(.horizontal, HassTokens.Spacing.l)
                .padding(.vertical, HassTokens.Spacing.s)
        }
    }
}
