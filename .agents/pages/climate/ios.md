# Climate (iPhone, iPhone Duo and iPad)

> **What:** how the Climate spec is built natively. **Read when:** changing `HassUI/Features/Climate` or `HassCore/Climate`.

## Code

| Piece | File |
|---|---|
| Entity ids, rooms, copy, tabs, option presentation | `HassCore/Config/ClimateConfig.swift` |
| Pure rules (effective away, notices, tracking summary, options, predictive metrics and bullets) | `HassCore/Climate/ClimateLogic.swift` |
| Actions and optimistic state over one `HassServiceCalling` | `HassCore/Climate/ClimateController.swift` |
| Page | `HassUI/Features/Climate/ClimateScreen.swift` (`ClimateScreen` binds the connection; `ClimatePage` takes a controller) |
| Sheet, tabs, detail pages | `HassUI/Features/Climate/ClimateSheet.swift` |
| Notice, toggle and opener tiles, hub pill, option picker | `HassUI/Features/Climate/ClimateComponents.swift` |
| Gallery and fixtures | `HassUI/Features/Gallery/ClimateGallery.swift` |

## Native decisions

- **Always full width, push** ([split-view](../../design/apple/split-view.md)); the advanced controls are a `.large` sheet with its own `NavigationStack` ([modal-sheet](../../patterns/modal-sheet.md)), so every device and pose is single page inside the sheet. HIG: Sheets, Navigation.
- Tabs use the shared `SheetTabPicker` (segmented; a menu at accessibility sizes). HIG: Segmented controls.
- Dials reuse `ClimateThermostatDial` (page size for Whole Home, modal size in a room), passing `action` for the Whole Home action line and the controller's `caller`. HIG: Accessibility › VoiceOver (adjustable handles).
- Tiles reuse `GlassTile` / `RemoteGlassTile`: toggles are switches with On/Off values, eco options and picker choices are selected, contact and vent cards are read-only (not buttons), openers have a chevron. Predictive Comfort's power button is a separate 52 pt button labelled "Turn off Predictive Comfort". HIG: Toggles, Buttons.
- The hub's HVAC mode picker is a full-height sheet of option tiles that stays open after a choice, matching the web; the fan picker closes. A `Menu` would close on selection. HIG: Pickers, Sheets.
- Grids use `DynamicGridLayout` with `@ScaledMetric` minimum widths, so two-column grids drop to one at AX5 instead of clipping. The sheet column caps at 720 pt on iPad (HIG: Layout, readable width).
- The hub pill stacks its pickers under its title at accessibility sizes.

## Tests

- Unit: `HassCoreTests/ClimateLogicTests.swift` (config, formatting, effective away, notices, contacts, tracking summary counts, option presentation, predictive metrics and reason bullets), `ClimateControllerTests.swift` (toggle, explicit switch, select, hub mode/fan, revert, failure, unavailable).
- Hosted: `HassUITests/ClimateViewTests.swift` renders the page (both fixtures, phone and tablet, AX5), every tab, every detail route, the option picker, plus fan-out, routing and the gallery recorder's climate echoes.
- Journeys: `Apps/iOSUITests/ClimateJourneyTests.swift` on the gallery (`FENTON_GALLERY=climate`; `FENTON_GALLERY_CLIMATE_OPEN=<tab|route>`, `FENTON_GALLERY_CLIMATE_SCENARIO=away`, `FENTON_GALLERY_CLEAN=1`) for everything that taps a control; one signed-in journey only reads the live page. Audits (with the AX5 relaunch) cover the page (home and away), hub picker, each tab, a room, Predictive Comfort, an eco option page and a tracking page; iPad also in landscape.
- Screenshots: `testCaptureClimateScreens` names `climate-<view>-<orientation>`; the host renames them `climate-<view>-<device>.png`.
