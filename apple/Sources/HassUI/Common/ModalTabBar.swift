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
    @Binding var selection: Item
    var identifier: String
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let form = ModalTabBarStyle.form(hasSymbols: symbol != nil, compactWidth: sizeClass == .compact,
                                         accessibilitySize: typeSize.isAccessibilitySize)
        if form == .menu {
            // Titles, not icons: at accessibility sizes the section names are what a reader needs (owner, 2026-10-16:
            // "keep text labels ... at accessibility sizes where the existing menu fallback applies").
            Picker(label, selection: $selection) {
                ForEach(tabs) { tab in
                    Text(title(tab)).tag(tab)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, minHeight: HassTokens.minTarget, alignment: .leading)
            .accessibilityIdentifier(identifier)
            // The same glass as the segmented bar, so content scrolling under the bottom bar stays behind it.
            .padding(.horizontal, HassTokens.Spacing.m)
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
    }

    /// The form for the environment.
    /// - Parameters:
    ///   - hasSymbols: The caller supplied an SF Symbol per section.
    ///   - compactWidth: Compact horizontal size class (iPhone, folded Duo).
    ///   - accessibilitySize: An accessibility Dynamic Type size.
    static func form(hasSymbols: Bool, compactWidth: Bool, accessibilitySize: Bool) -> Form {
        if accessibilitySize { return .menu }
        return hasSymbols && compactWidth ? .icons : .text
    }
}

extension View {
    /// Pins a ``ModalTabBar`` to this modal page, along the bottom edge by default (direction G). Apply it after
    /// ``modalChrome()`` so the content fades out under the tab bar as well as the title.
    func modalTabBar<Item: Hashable & Identifiable>(
        _ tabs: [Item], label: String, title: @escaping (Item) -> String, symbol: ((Item) -> String)? = nil,
        selection: Binding<Item>, identifier: String, placement: ModalTabBarPlacement = .bottom
    ) -> some View {
        safeAreaInset(edge: placement == .top ? .top : .bottom, spacing: 0) {
            ModalTabBar(tabs: tabs, label: label, title: title, symbol: symbol, selection: selection, identifier: identifier)
                .padding(.horizontal, HassTokens.Spacing.l)
                .padding(.vertical, HassTokens.Spacing.s)
        }
    }
}
