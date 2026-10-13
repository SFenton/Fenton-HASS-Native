import HassDesign
import SwiftUI

// MARK: - Modal tab bar

/// The one section switcher for a tabbed modal (media remote, thermostat advanced controls, vacuum; pattern:
/// `.agents/patterns/modal-sheet.md`).
///
/// The web puts its `ModalIconTabNav` at the bottom of the modal; native keeps a segmented control at the top,
/// pinned under the header (``SwiftUI/View/modalTabBar(_:label:title:symbol:selection:identifier:)``). HIG
/// Segmented controls (iOS, iPadOS): "Consider it for switching between closely related subviews; use a tab bar
/// for completely separate app sections", and HIG Tab bars: "Use tabs for navigation, not current-view actions",
/// navigating "an app's top-level sections". A modal's sections are closely related views of one device, so a
/// bottom tab bar there would read as app navigation.
///
/// Segments show text, or icons when the caller passes `symbol` (the vacuum's labels are too long for five
/// segments). HIG Segmented controls: "Prefer text or images, not a mix, in one control" and "Limit segments:
/// ... about 5 on iPhone". Icon segments still carry their names for VoiceOver. At accessibility text sizes,
/// where segments cannot grow, the control becomes a menu that names the selected section.
struct ModalTabBar<Tab: Hashable & Identifiable>: View {
    var tabs: [Tab]
    /// Spoken name of the control, e.g. `Thermostat sections`.
    var label: String
    var title: (Tab) -> String
    /// SF Symbol per tab; nil shows text segments.
    var symbol: ((Tab) -> String)?
    @Binding var selection: Tab
    var identifier: String
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            Picker(label, selection: $selection) {
                ForEach(tabs) { tab in
                    if let symbol {
                        Label(title(tab), systemImage: symbol(tab)).tag(tab)
                    } else {
                        Text(title(tab)).tag(tab)
                    }
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, minHeight: HassTokens.minTarget, alignment: .leading)
            .accessibilityIdentifier(identifier)
        } else {
            Picker(label, selection: $selection) {
                ForEach(tabs) { tab in
                    if let symbol {
                        Image(systemName: symbol(tab))
                            .accessibilityLabel(title(tab))
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
        }
    }
}

extension View {
    /// Pins a ``ModalTabBar`` under this modal page's header. Apply it after ``modalChrome()`` so the content
    /// fades out under the tab bar as well as the title.
    func modalTabBar<Tab: Hashable & Identifiable>(
        _ tabs: [Tab], label: String, title: @escaping (Tab) -> String, symbol: ((Tab) -> String)? = nil,
        selection: Binding<Tab>, identifier: String
    ) -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            ModalTabBar(tabs: tabs, label: label, title: title, symbol: symbol, selection: selection, identifier: identifier)
                .padding(.horizontal, HassTokens.Spacing.l)
                .padding(.vertical, HassTokens.Spacing.s)
        }
    }
}
