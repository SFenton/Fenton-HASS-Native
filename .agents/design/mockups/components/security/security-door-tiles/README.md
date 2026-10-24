# Door tiles (LockTile, GarageDoorTile)
> **What:** a lock or garage door as a tile in the Doors and windows family, with garage command feedback. **Read when:** you change `SecurityDoorTile`, `GarageDoorTile` or the garage controller's feedback.
- Mockup: [security-door-tiles.html](security-door-tiles.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/Security/SecurityDoorTile.swift`, `SecurityTiles.swift`, `HassCore/Security/GarageDoorController.swift`, `HassDesign/GlassTile.swift` · Spec: `.agents/pages/security/ios.md`, `spec.md` · Patterns: entity-tile, optimistic-actions, dynamic-grid, motion
- States covered: lock (six), garage (five), command feedback (sending, error, pending), vehicle (hidden), loading (pending bar), offline, long-text, ax5; page and sheet surfaces
- Motion: fill and glyph swap (state 0.6 s), error face (hold 8 s), pending pulse (1.4 s)
- Devices: iPhone and iPad size classes (swatches, no device frame)
- Open notes: SecurityConfig.Tone colours are unused by any view (tests only); garage doors open with no confirmation by spec
