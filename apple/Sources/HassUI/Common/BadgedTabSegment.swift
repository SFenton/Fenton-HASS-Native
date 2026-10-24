import HassDesign
import SwiftUI

/// One segment of ``BadgedTabSegments``: an icon (with its count badge) and/or a title, at least 44 pt tall, named for
/// VoiceOver with its count ("Overdue Chores, 3 items") and marked selected.
struct BadgedTabSegment: View {
    var title: String
    var symbol: String?
    var badge: Int
    var showsTitle: Bool
    var isSelected: Bool
    var lift: Namespace.ID
    var identifier: String
    var action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: select) {
            VStack(spacing: 2) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(showsTitle ? .body : .title3)
                        .overlay(alignment: .topTrailing) { SegmentBadge(count: badge) }
                }
                if showsTitle {
                    Text(title)
                        .font(.caption.weight(isSelected ? .semibold : .regular))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .foregroundStyle(isSelected ? HassTokens.Ink.primary : HassTokens.Ink.secondary)
            .frame(maxWidth: .infinity, minHeight: showsTitle && symbol != nil ? ModalTabBarStyle.titledSegmentHeight : ModalTabBarStyle.iconSegmentHeight)
            .background {
                if isSelected {
                    Capsule()
                        .fill(HassTokens.Surface.sheetCell)
                        .matchedGeometryEffect(id: "selected", in: lift)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(ModalTabBarStyle.accessibilityTitle(title, badge: badge))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }

    /// The selected segment glides to the new one; under Reduce Motion it jumps (HIG Motion).
    private func select() {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.2), action)
    }
}

/// The count on a segment's icon, "9+" past nine; nothing for none. Hidden from VoiceOver because the segment's own name
/// speaks the count.
private struct SegmentBadge: View {
    var count: Int

    var body: some View {
        if let text = ModalTabBarStyle.badgeText(count) {
            Text(text)
                .font(.caption2.bold())
                .dynamicTypeSize(...DynamicTypeSize.xLarge)
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .frame(minWidth: 16, minHeight: 16)
                .background(HassTokens.Ink.badge, in: Capsule())
                .offset(x: 10, y: -8)
                .accessibilityHidden(true)
        }
    }
}
