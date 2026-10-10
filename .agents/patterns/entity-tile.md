# Entity tile

> **What:** the glass tile used for entity controls. **Read when:** showing an entity as a tappable tile.

- `GlassTile(title:subtitle:symbol:tint:isActive:)` draws `.regularMaterial` with a tinted icon when active.
- Semantics follow the web UX contract: chevrons only for navigate/modal; toggles expose `.isToggle` and their on/off value; unavailable entities are dimmed and not tappable.
- Tile size stays stable while values update.
