import SwiftUI

/// A page's row of status chips: it scrolls sideways in compact width and wraps in regular width, and on a window with a
/// hinge it stops ``ChipRailMetrics/hingeGap`` short of the fold (the unfolded iPhone Duo's two halves each stay whole).
///
/// Pass the chips as ordinary children. Home, Security and room pages share it.
public struct ChipRail<Content: View>: View {
    private var content: Content
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.windowHinge) private var hinge
    @State private var measuredInset: CGFloat = 0

    /// Creates a rail.
    /// - Parameter content: The chips.
    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        let mode = ChipRailMode.resolve(isRegularWidth: horizontalSizeClass == .regular)
        layout(mode)
            .padding(.trailing, ChipRailMetrics.appliedInset(measured: measuredInset, hinge: hinge))
            .frame(maxWidth: .infinity, alignment: .leading)
            // Measured on the full-width frame outside the padding, so the inset never feeds back into the frame it is
            // computed from (measuring inside the padding oscillated and pinned the main thread on the unfolded Duo).
            // Only a window with a hinge measures: a window-space frame is recomputed on every frame the page scrolls.
            .background {
                if hinge != nil {
                    Color.clear
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            ChipRailMetrics.trailingInset(railFrame: proxy.frame(in: .global), hinge: hinge)
                        } action: { measuredInset = $0 }
                }
            }
    }

    @ViewBuilder
    private func layout(_ mode: ChipRailMode) -> some View {
        switch mode {
        case .scroll:
            scrollingRow
                .accessibilityIdentifier("chipRail.scroll")
        case .wrap:
            FlowLayout(spacing: HassTokens.Spacing.s) { content }
                .padding(.horizontal, HassTokens.Spacing.l)
        }
    }

    private var row: some View {
        HStack(spacing: HassTokens.Spacing.s) { content }
            .padding(.horizontal, HassTokens.Spacing.l)
    }

    /// The sideways row. On iOS the scrolling is UIKit's, so a drag never touches the page's view graph
    /// (``HostedHorizontalScroll``); elsewhere a SwiftUI `ScrollView`.
    @ViewBuilder
    private var scrollingRow: some View {
        #if os(iOS)
        // The scroll view clips to its frame, so chips never scroll under the folded iPhone Duo's trailing toolbar rail.
        HostedHorizontalScroll(content: row)
        #else
        ScrollView(.horizontal, showsIndicators: false) { row }
            .clipped()
        #endif
    }
}
