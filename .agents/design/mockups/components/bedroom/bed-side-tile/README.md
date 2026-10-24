# Bed side and wake light tiles (component)
> **What:** BedSideTile and WakeLightTile: GlassTile navigation tiles in the heating, cooling and lights families. **Read when:** you change the Master Bedroom tiles or their subtitles.
- Mockup: [bed-side-tile.html](bed-side-tile.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/Bedroom/BedSideSheet.swift`, `apple/Sources/HassUI/Features/Bedroom/WakeLightSheet.swift` · Spec: .agents/patterns/bedroom-devices.md, entity-tile.md · Patterns: bedroom-devices, entity-tile, motion
- States covered: bed states (heating, idle, cooling, off, unavailable, ringing, hot flash, Solo Trip), wake states (armed, active, recovering, none, blocked, vacation, unavailable), in the Sleep & Wake grid, ax5
- Motion: tile colour fade (state 0.6 s), countdown tick (no animation)
- Devices: iPhone and iPad size classes
- Open notes: idle tile is filled (doc says dark); ringing does not change the tile
