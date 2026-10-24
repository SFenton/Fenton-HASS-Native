# Security (page)
> **What:** the Security tab: Security and Contact Sensors chips, the alarm card, Doors as tiles, guests, cameras (Mach-E hidden). **Read when:** you change `SecurityPage`, the door tiles or the alarm card on the page, or need the page's states on every device.
- Mockup: [security.html](security.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/Security/SecurityScreen.swift`, `SecurityDoorTile.swift`, `SecurityTiles.swift`, `SecuritySystemSheet.swift`, `HassUI/Features/Home/GuestPresenceSection.swift`, `CameraGrid.swift`, `HassCore/Config/SecurityConfig.swift`, `HassCore/Security/GarageDoorController.swift`
- Spec: `.agents/pages/security/spec.md`, `ios.md`, `.agents/design/direction-g.md` · Patterns: status-rail, dynamic-grid, camera-streams, entity-tile, optimistic-actions, motion
- States covered: default, loading (pending bars on tiles, Unavailable card), refreshing, error, offline, reconnecting (and was), long-text (triggered, jam, moving doors), disarmed, armed away and night, triggered, doors open, garage sending and error, guests, mach-e (gallery only), ax5
- Motion: alarm mode and triggered wash (state 0.6 s), door tile fill and glyph swap, garage sequence (1 s, 2 s, 8 s timings), contact chip colour. Transitions: Security and Contact sheets, camera sheet, Disarm alert, tab cut
- Devices: iPhone, Duo folded, Duo unfolded landscape and portrait, iPad portrait and landscape; always one column (never splits)
- Open notes: AlarmPanel and the chips ignore `valuesPending` (first sign-in reads Unavailable, tiles show pending bars); the card has no max width on the page; spec's "Security" section differs from the native card plus Doors
