# Quick Links sheet (modal)

> **What:** the header button's sheet: up to seven solid-colour tiles; Rooms and Security System push inside, the rest open pages. **Read when:** you change Quick Links tiles, colours or routing.

- Mockup: [quick-links.html](quick-links.html) · shipped · reviewed 2026-10-23 (author draft; skill reviewers replace it)
- Source: `apple/Sources/HassUI/` Features/Rooms/QuickLinksSheet.swift; HassDesign/QuickLinkPalette.swift; HassCore/Rooms/RoomNavigation.swift
- Spec: .agents/pages/rooms/ios.md, .agents/design/direction-g.md · Patterns: modal-sheet, entity-tile, dynamic-grid
- States covered: default, loading, error, offline, sprinklers-hidden, armed-away/night, disarmed, triggered, redacted, food-counts, medium/large/fitted (large only), closed, ax5; dark and light
- Motion: Security colour follows the alarm; transitions: present, Rooms push, Security push, page link (sheet closes then pushes), dismiss
- Devices: iPhone, Duo folded, Duo unfolded landscape, iPad portrait and landscape
- Open notes:
  - Pushed levels show Back and no Close (Close is on the root view only): read from code, confirm on device.
- Shared helper: `pages/rooms/_rooms.js` (rooms batch; list of kit promotions in its header).
