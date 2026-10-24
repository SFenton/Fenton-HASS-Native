# Master Bedroom room page (page)

> **What:** the Master Bedroom with the wake light, SleepyPod bed sides, Apple TV and humidifier cards. **Read when:** you change the bedroom lane's tiles on the room page.

- Mockup: [room-master-bedroom.html](room-master-bedroom.html) · shipped · reviewed 2026-10-23 (author draft; skill reviewers replace it)
- Source: `apple/Sources/HassUI/` RoomScreen.swift; RoomTiles.swift (RoomCardView); Features/Bedroom/*; HassCore/Bedroom/BedSideController.swift; HassDesign/ThermostatTileFace.swift
- Spec: .agents/patterns/bedroom-devices.md, .agents/pages/rooms/ios.md · Patterns: bedroom-devices, room-device-sheets, entity-tile
- States covered: default, loading, refreshing, error, offline, reconnecting (+ was), beds-idle, beds-off, hot-flash, solo-trip, viewer-steph, wake-ramping/snoozed/blocked, media-playing, window-open, long-text, ax5, placeholder
- Motion: bed power, bed family swap, hot flash countdown; transitions: wake-light sheet, bed sheet, wake light to bed (queued)
- Devices: iPhone, Duo folded, Duo unfolded landscape and portrait, iPad portrait and landscape
- Open notes:
  - The wake light card never fills (generic rule); catalog hints "ringing" and "armed" are not on the card.
  - Bed tiles need a response-capable caller; otherwise generic climate cards.
- Shared helper: `pages/rooms/_rooms.js` (rooms batch; list of kit promotions in its header).
