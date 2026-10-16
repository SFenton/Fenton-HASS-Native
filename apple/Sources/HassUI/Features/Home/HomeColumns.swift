import CoreGraphics

/// Home's two columns on the unfolded iPhone Duo in landscape (direction G mockup n1-duo-unfolded; plan Phase 4,
/// decision 5): chips and weather lead, cameras and guests trail, and nothing straddles the hinge.
///
/// Built on ``SplitPolicy/geometry(container:isRegularWidth:hinge:)`` so it is geometric, never a device-name check, and
/// follows the same rules as the on-demand split (regular width, wider than tall, each half at least 360 pt). Unlike
/// the split it applies only where a hinge divides the window: iPad landscape stays one column (n1-ipad-home).
enum HomeColumns {
    /// The column widths when Home splits on a hinge, else nil (one column).
    /// - Parameters:
    ///   - container: The space Home's content is offered, in window coordinates.
    ///   - isRegularWidth: Horizontal size class is regular.
    ///   - hinge: The window's hinge in window coordinates, if any.
    static func resolve(container: CGRect, isRegularWidth: Bool, hinge: CGRect?) -> SplitGeometry? {
        guard hinge != nil,
              let geometry = SplitPolicy.geometry(container: container, isRegularWidth: isRegularWidth, hinge: hinge),
              geometry.isHinge else { return nil }
        return geometry
    }
}
