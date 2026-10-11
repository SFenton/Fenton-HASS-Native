# Vacation and Solo Trip (iPhone and iPad)

> **What:** Settings → Vacation: the chooser, Vacation Mode and Solo Trip. **Read when:** changing `HassUI/Features/Vacation` or `HassCore/HouseholdAway`.

Spec: [spec.md](spec.md) (web source `ha-sfenton-react-dash@9ac2a46`).

## Native

- **Entry.** Settings lists Vacation (`settings.vacation`, `VacationRoute`). `VacationScreen` re-resolves the route on live state (`Vacation.route`, web `vacationFeaturePath`): an engaged vacation or Solo Trip skips the chooser, and the root swaps if the state changes while it is shown. Once an engaged page has shown, turning that mode off keeps it (`lastEngaged`) instead of dropping the person back on the chooser, as the web stays on `vacation-mode` / `solo-trip`.
- **Logic lives in HassCore**, so it is unit tested without UI:
  - `HouseholdAwayController`: the one path to `script.household_away_command` (`return_response`, `HassConnection.callServiceWithResponse`, sent once with no retry), revision floor, one command at a time, 10 s timeout → unknown outcome. Shared with the bedroom pages (Sleepypod commands can be added as new `HouseholdAway.Command` cases).
  - `VacationModeController` (web `VacationModePage`): optimistic mode and checklist (`OptimisticOverlay`, live-change clear, 2 s revert), blocked enable, confirmation draft, inline date saves and invalid-date recovery.
  - `SoloTripController` (web `SoloTripPage`): traveler selection, editor, awaiting-echo states reconciled on every sensor change, optimistic end (60 s revert), return-time edits, restore choice. `SoloTripStatus` / `SoloTripNotice` mirror `SoloTripStatusSection` / `SoloTripActiveNotice`.
- **Layout.** Each page is two sections in a `DynamicGridLayout` (min 340 pt, 2 columns), so they sit side by side on iPad and unfolded Duo and stack on iPhone and folded Duo (web `ResponsiveSectionGrid`). Not a split view: the pages are Settings details and push in every pose until the Settings leading-pane split lands (split-view.md). HIG: Layout.
- **Sheets.** Confirm Vacation and Schedule Solo Trip are `.sheet`s with Cancel (HIG: Sheets; a form sheet on iPad). The Solo Trip sheet stays open and cannot be swiped away while the schedule waits for Home Assistant's echo.
- **Controls.** Vacation Mode and Solo Trip are `GlassTile` toggles; travelers are `GlassTile`s with the `.isSelected` trait added locally until `GlassTile` gets its `.selection` kind (owned by the room pages lane); checklist rows are toggle buttons with Checked / Not checked values (HIG: Toggles).
- **Dates** use `ScheduleDateFields` ([pattern](../../patterns/schedule-date-fields.md)). Fields that write to Home Assistant at once (Vacation Dates, Solo Trip return) commit after 0.9 s without a change, so turning a wheel sends one call (spec open question 1). The sheets keep drafts and send on confirm.
- **Departure from web:** none in behavior. "Learn More" in the setup subtitle has no link on the web either (spec open question 2).

## Tests

- Unit (`HassCoreTests`): `HouseholdAwayContractTests`, `HouseholdAwayControllerTests`, `VacationConfigTests`, `VacationModeControllerTests`, `SoloTripControllerTests`.
- Hosted (`HassUITests/VacationViewTests`): every page in every fixture scenario, both sheets, the gallery house's echoes.
- Journeys (`VacationJourneyTests`) run on the `vacation` gallery page (`FENTON_GALLERY=vacation`, `FENTON_GALLERY_AWAY=<scenario>`): a fixture house that echoes like Home Assistant, so no journey changes the real house. Audits with AX5 relaunch on every page and sheet, AX5 reachability, screenshots (`vacation-<page>-<orientation>`). One read-only live journey opens Settings → Vacation on the real server.
