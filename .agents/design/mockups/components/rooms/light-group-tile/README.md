# Light and light-group tile (component)
> **What:** one light or a room's group light: a brightness tile when it dims, else a power tile. **Read when:** you change `LightGroupTile` or `BrightnessTile` use in a room page or sheet.
- Mockup: [light-group-tile.html](light-group-tile.html) · status shipped · reviewed 2026-10-23
- Source: `HassUI/Common/RoomOverview/LightGroupTile.swift`, `HassDesign/BrightnessTile.swift`, `HassCore/Lights/LightControl.swift` · Spec: `.agents/patterns/room-overview-sheet.md`, `.agents/patterns/entity-tile.md` · Patterns: entity-tile, room-overview-sheet, optimistic-actions
- States covered: brightness (off, 30, 80, coloured bulb, unavailable), dragging, power tile, group slab, titles (nightstand, long), in-context page, ax5; sheet surface, dark and light
- Motion: drag brightness (quick 0.2 s), tap power (state 0.6 s)
- Devices: size class via the Device control (iPhone, iPad)
- Open notes: kit BrightnessTile text and bubble differ from the app (rewritten here); which lights dim is a fixture
