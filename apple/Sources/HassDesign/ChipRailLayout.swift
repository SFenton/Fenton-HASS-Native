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

    /// The inset a rail applies: the measured one while the window has a hinge, else none (a window without a hinge
    /// does not measure, so a value left from a fold that has since closed must not linger).
    /// - Parameters:
    ///   - measured: The last ``trailingInset(railFrame:hinge:gap:)`` the rail measured.
    ///   - hinge: The window's hinge, if any.
    public static func appliedInset(measured: CGFloat, hinge: CGRect?) -> CGFloat {
        hinge == nil ? 0 : measured
    }

    /// The content size of the UIKit scroll view behind a compact rail: at least as wide as the scroll view (so a
    /// short row still fills it and nothing bounces) and as tall as the scroll view.
    /// - Parameters:
    ///   - natural: The chips' natural size.
    ///   - bounds: The scroll view's bounds.
    public static func hostedContentSize(natural: CGSize, bounds: CGSize) -> CGSize {
        CGSize(width: max(natural.width, bounds.width), height: bounds.height)
    }

    /// Where the hosted chips sit inside that content: at the leading edge, whatever the row's width.
    ///
    /// A hosting view wider than its content centres the content, so a row that fits (Security's two chips) drew
    /// centred on the page instead of starting at the margin (owner, 2026-10-17). The hosted view is exactly the
    /// row's natural width, so the chips start at the leading edge: the left in a left-to-right layout, the right in a
    /// right-to-left one.
    /// - Parameters:
    ///   - natural: The chips' natural size.
    ///   - bounds: The scroll view's bounds.
    ///   - isRightToLeft: Whether the layout direction runs right to left.
    public static func hostedContentFrame(natural: CGSize, bounds: CGSize, isRightToLeft: Bool = false) -> CGRect {
        let content = hostedContentSize(natural: natural, bounds: bounds)
        let width = min(natural.width, content.width)
        return CGRect(x: isRightToLeft ? content.width - width : 0, y: 0, width: width, height: content.height)
    }

    /// The horizontal offset that shows a row's leading edge: zero left to right; at the far end right to left, where
    /// the row starts at the right and a `UIScrollView` still counts offsets from the left.
    /// - Parameters:
    ///   - contentWidth: The scroll view's content width.
    ///   - boundsWidth: The scroll view's width.
    ///   - isRightToLeft: Whether the layout direction runs right to left.
    public static func hostedLeadingOffset(contentWidth: CGFloat, boundsWidth: CGFloat, isRightToLeft: Bool) -> CGFloat {
        isRightToLeft ? max(0, contentWidth - boundsWidth) : 0
    }
}
