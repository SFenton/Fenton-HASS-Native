import CoreGraphics

// MARK: - Hinge

/// iPhone Duo hinge status, platform-neutral so policies test on macOS.
public enum HingeState: Sendable, Hashable {
    case closed
    case partiallyOpen
    case fullyOpen
}

// MARK: - Split policy

/// When a page may show its on-demand split (owner rules, 2026-10-10; `.agents/design/apple/split-view.md`).
///
/// | Device / pose | Split |
/// |---|---|
/// | iPhone (portrait-locked) | never |
/// | iPhone Duo folded (outer display) | never |
/// | iPhone Duo unfolded portrait | never |
/// | iPad portrait | never |
/// | iPhone Duo unfolded landscape, iPad landscape | allowed |
///
/// Expressed by geometry, never by device name: a split needs a regular-width window that is wider
/// than tall, with each half at least ``minimumPaneWidth``. iPad Split View/Stage Manager windows
/// follow the same rule from their own size.
public enum SplitPolicy {
    /// Narrowest pane a split may produce (FestivalNativeApps `OnDemandSplitPolicy`).
    public static let minimumPaneWidth: CGFloat = 360

    /// Whether the window may split.
    /// - Parameters:
    ///   - size: The window (or content area) size in points.
    ///   - isRegularWidth: Horizontal size class is regular.
    public static func allowsSplit(size: CGSize, isRegularWidth: Bool) -> Bool {
        guard isRegularWidth, size.width > size.height else { return false }
        return size.width / 2 >= minimumPaneWidth
    }

    /// Where the divider sits: the hinge's x when a vertical fold crosses the window, else the midpoint.
    /// - Parameters:
    ///   - width: Content width.
    ///   - hingeMidX: The vertical fold's centre, if the device reports one inside the window.
    public static func dividerX(width: CGFloat, hingeMidX: CGFloat?) -> CGFloat {
        if let hingeMidX, hingeMidX > 0, hingeMidX < width { return hingeMidX }
        return width / 2
    }
}
