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
| Page notice, Thermostat Hub list and its pop-up menus | `HassUI/Features/Climate/ClimateComponents.swift` |
| Gallery and fixtures | `HassUI/Features/Gallery/ClimateGallery.swift` |

## Native decisions

- **Always full width, push** ([split-view](../../design/apple/split-view.md)); the advanced controls are a `.large` sheet with its own `NavigationStack` ([modal-sheet](../../patterns/modal-sheet.md)), so every device and pose is single page inside the sheet. HIG: Sheets, Navigation.
- Direction G (mockup n3). Page: "Whole Home" with the dial on a module, the Thermostat Hub and Fan rows (`ClimateHubList`, a `ModuleList`), the away notice and the integration warning (`ClimateNotice`, dense when a warning), open contacts as contact-family `GlassTile`s (read-only, not buttons), then "Advanced Controls" rows that open the sheet on their tab.
- The hub's mode and fan are pop-up menus (`HubPicker`: a `Menu` holding an inline `Picker`, so the current choice is checked and read as selected; the label is the value and an up-down chevron at 44 pt, since a bare `Picker(.menu)` keeps a smaller UIKit hit area). HIG: Pop-up buttons.
- Sheet: dark system `Form`s (the sheet's ground and cells) with section text in `FormHeader` / `FormFooter`; the tabs are the shared bottom `modalTabBar` (segmented; a menu at accessibility sizes); titles are inline bar titles. Toggles are system switches (`homeassistant.toggle`; Predictive Comfort sends `switch.turn_on` / `turn_off`, and "Current Prediction" shows while it is on). Eco options are checkmark rows that read the choice and its description; tracking rooms are checkmark buttons with On/Off values; vents and metrics are read-only `LabeledContent`. Missing selects or disabled tracking show an `InlineAlert`. HIG: Toggles, Lists.
- Dials reuse `ClimateThermostatDial` (page size for Whole Home, modal size in a room), passing `action` for the Whole Home action line and the controller's `caller`. HIG: Accessibility › VoiceOver (adjustable handles).
- The page and sheet columns cap at 720 pt on iPad (HIG: Layout, readable width).

## Tests

- Unit: `HassCoreTests/ClimateLogicTests.swift` (config, formatting, effective away, notices, contacts, tracking summary counts, option presentation, predictive metrics and reason bullets), `ClimateControllerTests.swift` (toggle, explicit switch, select, hub mode/fan, revert, failure, unavailable).
- Hosted: `HassUITests/ClimateViewTests.swift` renders the page (both fixtures, phone and tablet, AX5), every tab, every detail route, the hub pop-up menus, plus fan-out, routing and the gallery recorder's climate echoes.
- Journeys: `Apps/iOSUITests/ClimateJourneyTests.swift` on the gallery (`FENTON_GALLERY=climate`; `FENTON_GALLERY_CLIMATE_OPEN=<tab|route>`, `FENTON_GALLERY_CLIMATE_SCENARIO=away`, `FENTON_GALLERY_CLEAN=1`) for everything that taps a control; one signed-in journey only reads the live page. Audits (with the AX5 relaunch) cover the page (home and away), the open hub menu, each tab, a room, Predictive Comfort, an eco option page and a tracking page; iPad also in landscape.
- Screenshots: `testCaptureClimateScreens` names `climate-<view>-<orientation>`; the host renames them `climate-<view>-<device>.png`.
