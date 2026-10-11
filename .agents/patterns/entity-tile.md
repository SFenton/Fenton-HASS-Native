# Entity tile

> **What:** the glass tile used for entity controls. **Read when:** showing an entity as a tappable tile.

- `GlassTile(title:subtitle:symbol:tint:isActive:)` draws `.regularMaterial` with a tinted icon when active.
- Semantics follow the web UX contract: chevrons only for navigate/modal; toggles expose `.isToggle` and their on/off value; unavailable entities are dimmed and not tappable.
- Tile size stays stable while values update.
- Every entity tile draws through `GlassTileFace`; `BrightnessTile` (`HassDesign/BrightnessTile.swift`, web `LightBrightnessCard.tsx`) is the dimmable-light variant. Tap flips power, a horizontal drag sets brightness from the finger's position and commits on release, a vertical drag scrolls. The fill is the light's `rgb_color` (else the light tint) as a 32% wash so labels keep contrast. VoiceOver: activate flips power, adjust steps 10% (the web keyboard steps 5%; 10% keeps VoiceOver swipes practical). Value reads `Off`, `45%` or `Unavailable`. Gesture and optimistic state live in the pure `BrightnessInteraction` value type so tap, drag and adjust are unit-tested; the view only wires gestures and the pending timeout to it.
- `BrightnessTile(onOpen:)` makes a tap open the light's details instead of flipping power (web `tapAction: 'more-info'`, Custom Lights): the tile shows a chevron, VoiceOver's activate opens details and a "Turn On"/"Turn Off" custom action flips power; drag and adjust still set brightness.
- Light power is always an explicit `turn_on` / `turn_off` from the shown state via `LightControl` (`HassCore/Lights`), never `toggle`: Presence Based Lighting's Presence Lock reverts toggles in empty rooms and only honors a bare `turn_on` from an app user. Brightness 0 sends `turn_off`.
