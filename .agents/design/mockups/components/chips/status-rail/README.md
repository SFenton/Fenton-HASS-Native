# Status rail (component)
> **What:** the chip row under a page title: scrolls on compact width, wraps on regular, stops 24 pt short of a hinge, always starts at the leading margin. **Read when:** you change `ChipRail`, `StatusRail` or add chips to a page.
- Mockup: [status-rail.html](status-rail.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/Home/StatusRail.swift`, `apple/Sources/HassDesign/ChipRail.swift`, `ChipRailLayout.swift`, `HassUI/Features/Rooms/RoomTiles.swift` · Spec: `.agents/patterns/status-rail.md`, `.agents/design/apple/split-view.md` · Patterns: status-rail, dynamic-grid
- States covered: home (six chips), poses (iPhone scroll, iPad wrap, unfolded Duo with the hinge band), security (two chips), room rail, left-aligned few chips, loading, error (unavailable), long text, ax5
- Motion: chip colour, arrival slide, sideways scroll. Transition: opens a sheet (see Home)
- Devices: iPhone, Duo folded, Duo unfolded landscape, iPad portrait and landscape
- Open notes: the app hosts the compact row in UIKit (status-rail.md); the kit scrolls with CSS. Room rails draw each room's own overview cards (five shown for illustration)
