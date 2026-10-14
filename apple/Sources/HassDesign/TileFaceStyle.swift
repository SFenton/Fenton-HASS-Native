import SwiftUI

/// Which of direction G's tile faces a tile draws (`.agents/design/direction-g.md`, Controls: Tiles; pattern:
/// `.agents/patterns/entity-tile.md`).
///
/// Pure, so the choice is unit-tested apart from the drawing in ``GlassTileFace``.
public enum TileFaceStyle: Equatable, Sendable {
    /// Dark ground, glyph in the family colour mixed toward grey (or secondary without a family).
    case off
    /// A light that is on: the warm lit tile with dark ink.
    case lit
    /// A device that is on: filled with its family colour, with the family's ink.
    case filled(ColorFamily)
    /// A tile whose caller has not picked a family yet: dark ground with the caller's tint on the glyph and rim.
    case tinted
    /// Something is wrong (no response, a fault): dark dense ground, red glyph and red state.
    case error

    /// The face for a tile's state.
    /// - Parameters:
    ///   - family: The device's colour family, or nil when the caller passes only a tint.
    ///   - isActive: Whether the device is on.
    ///   - isError: Whether the tile reports a fault.
    ///   - isUnavailable: Whether the entity is unavailable (drawn off and dimmed).
    public static func resolve(family: ColorFamily?, isActive: Bool, isError: Bool, isUnavailable: Bool) -> Self {
        if isError { return .error }
        if isUnavailable || !isActive { return .off }
        guard let family else { return .tinted }
        if family == .lights { return .lit }
        return family.spec.fill == nil ? .tinted : .filled(family)
    }

    /// Black over the part of a white-ink filled face that progress has not reached, so the done part reads as
    /// the lighter band.
    public static let progressShade = 0.18
    /// White over the done part of a dark-ink filled face (power).
    public static let progressLighten = 0.25

    /// Whether text on this face is dark (the lit tile and power's yellow).
    public var hasDarkInk: Bool {
        switch self {
        case .lit: true
        case let .filled(family): family.spec.darkInk
        default: false
        }
    }
}
