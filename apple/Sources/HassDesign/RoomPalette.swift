import SwiftUI

/// One colour per room for navigation tiles (the Rooms grid, Climate's Advanced Controls rooms): a solid fill with a
/// white, filled glyph and white text (`.agents/design/direction-g.md`, Colour: Room tiles; owner, 2026-10-16: "room
/// tiles don't have nice colours, and icons should be filled/white").
///
/// **Source.** The web colours every room card from `AREA_ITEMS`
/// (`ha-sfenton-react-dash@f5a7bf9:src/constants/atAGlance.ts:324-340`) as `rgb(color / 0.6)` under white text
/// (`src/components/core/Card.module.css`, `.card`). Those raw values are not usable as tile fills: composited the
/// way the web draws them, seven of the sixteen miss 4.5:1 with white (Downstairs Hallway 2.9:1, Entryway 3.3:1,
/// Living Room 3.6:1) and Theater Room is `rgb(0 0 1)`, which is invisible on a dark tile. Each room here keeps its web
/// hue and is moved to a lightness where white holds at least 4.7:1, a chroma that reads as a colour, and a distance
/// of at least 0.05 (OKLab) from every other room and from every colour family and security mode fill, so a room
/// never reads as a device or as an alarm state. Theater Room (web black) and Master Bathroom (web grey) have no hue
/// to keep and take a deep plum and a slate.
///
/// Fixed fills with fixed inks: the tile looks the same on a page and in a light or dark sheet.
public enum RoomPalette {
    /// The fill for a room page path (`living-room`), as `0xRRGGBB`, or nil for a path that is not a room.
    public static func fill(forRoom path: String) -> UInt32? { fills[path] }

    /// The fill for a Climate room key (`living_room`) or a room page path.
    public static func fill(forKey key: String) -> UInt32? { fill(forRoom: key.replacingOccurrences(of: "_", with: "-")) }

    /// The fill as a colour.
    public static func color(forRoom path: String) -> Color? { fill(forRoom: path).map { Color(rgb: $0) } }

    /// Ink on every fill: white.
    public static let ink = Color.white

    /// All sixteen rooms by page path (web `AREA_ITEMS` order is the grid's default order).
    public static let fills: [String: UInt32] = [
        "living-room": 0x8A6F44,
        "guest-room": 0x0D8457,
        "gym": 0xAF5F00,
        "master-bedroom": 0x3E3EB7,
        "office": 0x007E94,
        "hallway": 0x72492D,
        "kitchen": 0x547F12,
        "music-room": 0x901E79,
        "garage": 0xA6222C,
        "theater-room": 0x453057,
        "back-deck": 0x195E20,
        "downstairs-hallway": 0x637145,
        "guest-bathroom": 0x407B6E,
        "master-bathroom": 0x59596F,
        "dining-room": 0x975B46,
        "entryway": 0x7D7200,
    ]
}
