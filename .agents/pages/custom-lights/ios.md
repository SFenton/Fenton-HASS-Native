# Custom Lights (iPhone and iPad)

> **What:** how the native Custom Lights page is built. **Read when:** changing `HassUI/Features/CustomLights`.

- Entities, swatches and service calls: `CustomLightsConfig` (`HassCore/Config/CustomLightsConfig.swift`), unit-tested.
- Manual control sends explicit `input_boolean.turn_on` / `turn_off` from the shown state instead of the web's `homeassistant.toggle` (same result; the app never toggles from a possibly stale state). Light power and brightness go through `LightControl` (never `toggle`; see [entity-tile](../../patterns/entity-tile.md)).
- Light tiles are `BrightnessTile(onOpen:)`: tap opens the sheet (chevron shown), drag sets brightness, VoiceOver activates to open and offers a "Turn On/Off" action.
- Lighting Mode opens `OptionPickerSheet` ([option-picker](../../patterns/option-picker.md)) at the medium detent.
- The light sheet uses the system `ColorPicker` instead of the web's hue wheel and RGB fields (HIG: Color wells: the system picker has a wheel, sliders, hex entry and eyedropper, and VoiceOver support). Picks are sent 250 ms after the picker settles so a drag does not flood the light. Departure from web parity, recorded here.
- Layout: content up to 960 pt wide; tiles in a `DynamicGridLayout` (min 150 pt, up to 4). Full-width push page in every pose; sheets everywhere.
- Tests: `CustomLightsConfigTests`, `HomePagesViewTests` (renders, color conversion, gallery recorder echoes), `HomePagesJourneyTests` (gallery `FENTON_GALLERY=custom-lights`, `FENTON_GALLERY_PICKER=1`, `FENTON_GALLERY_LIGHT=<entity>`).
