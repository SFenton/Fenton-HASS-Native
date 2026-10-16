import SwiftUI

/// How a chip rail lays its chips out (`.agents/patterns/status-rail.md`).
public enum ChipRailMode: Equatable, Sendable {
    /// One row that scrolls sideways: compact width (iPhone, the folded Duo), where chips would crowd the page.
    case scroll
    /// Rows that wrap, like words in a paragraph: regular width (iPad, the unfolded Duo), where every chip fits in view
    /// (HIG Layout: don't hide content off screen when there is room for it).
    case wrap

    /// The layout for a window.
    /// - Parameter isRegularWidth: Horizontal size class is regular.
    public static func resolve(isRegularWidth: Bool) -> ChipRailMode { isRegularWidth ? .wrap : .scroll }
}

/// Geometry for how a chip rail meets the iPhone Duo's hinge.
public enum ChipRailMetrics {
    /// How far a rail stops short of the hinge (direction G, Navigation: "the chip row stops 24pt short of the hinge").
    public static let hingeGap: CGFloat = 24

    /// The trailing inset that keeps a rail `gap` short of a vertical hinge it would otherwise reach.
    ///
    /// Zero when there is no hinge, when the hinge is horizontal, when the rail ends before the gap begins, or when the
    /// rail starts on the far side of it (a rail in the trailing column).
    /// - Parameters:
    ///   - railFrame: The rail's full-width frame in window coordinates.
    ///   - hinge: The window's hinge in the same coordinates, if any.
    ///   - gap: The space to leave before the hinge.
    public static func trailingInset(railFrame: CGRect, hinge: CGRect?, gap: CGFloat = hingeGap) -> CGFloat {
        guard let hinge, hinge.height >= hinge.width, hinge.minX > railFrame.minX else { return 0 }
        return max(0, railFrame.maxX - (hinge.minX - gap))
    }
}

/// A page's row of status chips: it scrolls sideways in compact width and wraps in regular width, and on a window with a
/// hinge it stops ``ChipRailMetrics/hingeGap`` short of the fold (the unfolded iPhone Duo's two halves each stay whole).
///
/// Pass the chips as ordinary children. Home, Security and room pages share it.
public struct ChipRail<Content: View>: View {
    private var content: Content
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.windowHinge) private var hinge
    @State private var trailingInset: CGFloat = 0

    /// Creates a rail.
    /// - Parameter content: The chips.
    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        let mode = ChipRailMode.resolve(isRegularWidth: horizontalSizeClass == .regular)
        layout(mode)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Measured before the trailing padding, so the inset never feeds back into the frame it comes from.
            .onGeometryChange(for: CGFloat.self) { proxy in
                ChipRailMetrics.trailingInset(railFrame: proxy.frame(in: .global), hinge: hinge)
            } action: { trailingInset = $0 }
            .padding(.trailing, trailingInset)
    }

    @ViewBuilder
    private func layout(_ mode: ChipRailMode) -> some View {
        switch mode {
        case .scroll:
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: HassTokens.Spacing.s) { content }
                    .padding(.horizontal, HassTokens.Spacing.l)
            }
            // A horizontal scroll view draws into the side safe areas; clip it to its frame so chips never
            // scroll under the folded iPhone Duo's trailing toolbar rail.
            .clipped()
        case .wrap:
            FlowLayout(spacing: HassTokens.Spacing.s) { content }
                .padding(.horizontal, HassTokens.Spacing.l)
        }
    }
}
