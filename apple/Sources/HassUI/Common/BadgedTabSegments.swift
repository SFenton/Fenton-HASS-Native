import HassDesign
import SwiftUI

/// The segments of a ``ModalTabBar`` with count badges: a segmented control's look (the selected segment lifted onto the
/// sheet's cell colour) built from buttons, so each segment can carry a badge and its own spoken name. The glass capsule
/// around them belongs to ``ModalTabBar``.
struct BadgedTabSegments<Item: Hashable & Identifiable>: View {
    var tabs: [Item]
    var title: (Item) -> String
    var symbol: ((Item) -> String)?
    var badge: (Item) -> Int
    /// An icon over its title (regular width); else the icon alone.
    var showsTitles: Bool
    @Binding var selection: Item
    var identifier: String
    /// Spoken name of the bar.
    var label: String
    @Namespace private var lift

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                BadgedTabSegment(
                    title: title(tab), symbol: symbol?(tab), badge: badge(tab), showsTitle: showsTitles || symbol == nil,
                    isSelected: tab == selection, lift: lift, identifier: "\(identifier).\(tab.id)"
                ) {
                    selection = tab
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}
