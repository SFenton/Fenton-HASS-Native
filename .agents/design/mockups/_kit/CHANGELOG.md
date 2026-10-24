# Kit changelog

> **What:** what changed in `_kit/`, newest first, so a mockup author knows which local workaround can go. Existing mockups keep rendering; the entries below list what looks different.

## v2 (2026-10-23)

**Loader (`kit.js`)**
- Deterministic ordered load: each file carries an `onerror` hook, a verify step re-writes the failed file and every file after it (up to four retries, brief back-off) before the page's own scripts run; `Mock.loadErrors` and the red banner report a final failure. Fixes `Mock.components.X is not a function` under parallel load. `file://` and the inline export are unchanged.

**CSS (`kit.css`)**
- Page-furniture selectors (`.k-wrap h1/h2/h3/p/code/a/ul/li/table/th/td`) no longer match inside `.screen`, `.k-device`, `.k-swatch`, `.k-plain`, `.ui-root`, `.ui-sheet`, `.in-sheet`, `.ui-host`. Section headers, SettingsSection titles and form headers inside frames lose the stray 44 pt margins and 22 px sizes (the kit rules now win).
- Grid: the scaled minimum is capped at the container width (`min(100%, ...)`): AX5 gives one full-width column and never overflows; same for the alarm mode grid. `TileGrid` equal rows keep `.gridheader` rows at their own height; the ResizeObserver work runs a frame later and only on a width or scale change (no loop warning on the Duo).
- Reduce Transparency: lit tiles keep the warm lit ground and ink, power tiles keep dark ink, error tiles keep the dense ground, and tiles in a sheet keep the sheet cell instead of the dark page solid. A power tile in a sheet keeps its dark ink in every mode.
- InlineAlert error icon is red; ImageCard AX thumbnail is 72 pt; weather hour time is 13 pt and temperature 17 pt; the weather numeral is capped at 96 pt at AX5.
- `.k-swatch` is a containing block, so overlays (flyout, scrims) stay inside their swatch in the gallery.

**Components**
- `BrightnessTile`: status line is the percent ("70%", "Off", "Unavailable"), bubble is a 60 x 32 capsule centred 24 pt above the tile (BrightnessBubble), `chevron: true` for the open-details tile; Reduce Motion drops the lift scale. `GlassTile` gains `showsChevron`.
- `CameraTile`: no state pill on the tile (CameraGrid draws only the name capsule and a red dot while live). The viewer's badge (Live, Live · Delayed, Last live 6:51 PM, Connecting, Snapshot) is `viewer: true`.
- `TabBar`: badge prints the number (system `.badge`), not "9+" (only the Profile button says 9+).
- `Alert`: every alert stacks its buttons at AX5 (reads `ctx.axSize`); optional `field`, plus `AlertField`.
- `AlarmPanel`: new `hidden` state (privacy redaction: "Hidden", neutral badge, buttons enabled).
- `ThermostatDial`: single `target` (one handle, no arc), `off`, `unavailable`, `dragging`; coloured 4 pt handle borders, status-coloured current marker with a dark rim, ring shadow, Light numeral, bold unit and a caption with a thermometer ("72.0°F" / "68.0 · 74.0"). Only a heat+cool range draws arcs in the app; `heat` or `cool` alone remain as a legacy arc.
- `WeatherCard`: 24 sample hours in pages (6 per page, 9 on regular width, scaled with text size) with the page-dot indicator and Previous and Next on regular width; pending is "--" with static placeholder hours and no briefing; `page`, `narrow`, `ctx` props.
- `Mock.page`: inline title in the bar that fades in as the large title scrolls under it; `collapsed: true` stages that state. `Mock.sheet` accepts a `ConfirmationDialog` as `alert` without a second scrim.

**New components (promoted from author helpers)**
- `ConfirmationDialog` (= `ActionSheet`), `ContentUnavailableView`, `AlertField` (in `Alert.js`), `SettingsLinkRow`, `TextToolbarButtons` / `TextToolbarButton`, `FullScreenCover` (+ `Mock.cover`). Callers of the helpers (`SA.actionSheet`, `HF.contentUnavailable`, `V.linkRow`, ...) are untouched; switch when you next edit them.

**Symbols (`lib/symbols.js`)**
- About 130 names added (303 total): every look-alike authors patched into `Mock.symbols` at run time was promoted verbatim (appliances, battery levels, windows, stairs, barcodes, sunrise and sunset, ...), and the rest were drawn. Local `if (!Mock.symbols[k])` patches become no-ops.

## v1 (2026-10-23)
- Shared kit, authoring spec and the first component set.
