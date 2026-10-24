# Custom Lights (page)
> **What:** Manual control of the front yard lights: a switch, the lighting mode, and in Custom mode a brightness tile per light plus Reset All Lights. **Read when:** you change `CustomLightsScreen`, `CustomLightsConfig` or the light tiles.
- Mockup: [custom-lights.html](custom-lights.html) · status shipped · reviewed 2026-10-23
- Source: `HassUI/Features/CustomLights/CustomLightsScreen.swift`, `HassCore/Config/CustomLightsConfig.swift`, `HassDesign/BrightnessTile.swift`, `ModuleList.swift` · Spec: `.agents/pages/custom-lights/spec.md`, `ios.md` · Patterns: module-list, dynamic-grid, entity-tile, option-picker
- States covered: default, manual-off, preset-mode, default-mode, loading (unavailable), refreshing, error, offline, reconnecting (+ was), dragging, long-text, ax5, closed
- Motion: mode swatch cross-fade (state), brightness drag (quick), manual toggle (no animation, flagged); transitions: push, tile to sheet, row to picker
- Devices: iPhone, Duo folded, Duo unfolded landscape and portrait, iPad portrait and landscape
- Open notes: no pending UI on this page (loading reads as unavailable); the kit BrightnessTile copy ("On at 70%") differs from the app ("70%"); shared helpers in `components/media/_media-lights-cameras.js` (promote to kit)
