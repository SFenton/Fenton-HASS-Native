import SwiftUI

public extension EnvironmentValues {
    /// The iPhone Duo hinge in window coordinates: the active fold while the inner display is partly
    /// folded, else the hinge the system reports while it lies flat. Nil on devices without one and on
    /// the folded Duo's outer display. On-demand splits put their divider here (FestivalNativeApps
    /// `DeviceLayout.splitHinge`; owner rule for this app, 2026-10-10: "on the hinge on the Duo").
    ///
    /// The shell publishes it (`readsWindowHinge()` in HassUI). Shared layout reads it too:
    /// ``DynamicGridLayout`` rounds its column count to an even number and ``ChipRail`` stops short of it, so
    /// nothing is laid out across the fold (`.agents/design/apple/duo.md`).
    @Entry var windowHinge: CGRect?
}
