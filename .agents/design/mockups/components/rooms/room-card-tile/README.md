# Room card tile and card view (component)

> **What:** a room card as a GlassTile in its colour family, plus the fan, garage and bed variants. **Read when:** you change a room card face or add a card kind.

- Mockup: [room-card-tile.html](room-card-tile.html) · shipped · reviewed 2026-10-23 (author draft; skill reviewers replace it)
- Source: `apple/Sources/HassUI/` Features/Rooms/RoomTiles.swift; RoomSupport.swift; BathroomFanRoomTile.swift; FanRailButton.swift; HassDesign/GlassTile.swift
- Spec: .agents/patterns/entity-tile.md, pages/rooms/spec.md · Patterns: entity-tile, optimistic-actions, dynamic-grid
- States covered: light off/on, modal, command, selection, state, wake light, unavailable, error, garage, fan (on, off, unavailable), bed heating/off, in-context (section, app launcher, sheet grid), ax5
- Motion: face cross-fade, glyph replace
- Devices: size class: iPhone, iPad
- Open notes:
  - Web state washes exist in RoomFormat but are not drawn.
- Shared helper: `pages/rooms/_rooms.js` (rooms batch; list of kit promotions in its header).
