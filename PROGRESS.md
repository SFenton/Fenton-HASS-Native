# Fenton HASS Native: plan and progress

Single source of truth for what is being built, by whom and in which order. Update the lane table and log whenever work lands on `main`.

## 1. Operating model

Opus plans and reviews; Sonnet lanes implement in separate worktrees on disjoint folders; Haiku gathers. See [AGENTS.md](AGENTS.md#model-roles).

### Lanes and file ownership

A lane may read anything but only edit what it owns. Shared seams are orchestrator-owned; ask in your final report if you need a change there.

```
apple/Package.swift, apple/project.yml                    → orchestrator
apple/Sources/HassCore/Auth, Connection, Entities          → orchestrator (Core lane once opened)
apple/Sources/HassCore/Config/<Area>Config.swift           → the lane porting that area
apple/Sources/HassDesign/                                  → orchestrator (lanes may add new files)
apple/Sources/HassUI/App/                                  → orchestrator
apple/Sources/HassUI/Features/<Feature>/                   → the lane for that feature
apple/Sources/HassCore/Config/MediaRemote*.swift,
apple/Sources/HassCore/MediaRemote/,
apple/Sources/HassUI/Features/MediaRemote/,
apple/Sources/HassUI/Features/Gallery/MediaRemoteGallery.swift → media remote lane (claude/project-thread-go5jtz)
apple/Sources/HassCore/Inventory/, apple/Sources/HassUI/Features/Inventory/,
apple/Sources/HassUI/Features/Gallery/InventoryGallery.swift → inventory lane (claude/project-thread-2tax3x)
apple/Sources/HassCore/Config/SecurityConfig.swift,
apple/Sources/HassCore/Security/,
apple/Sources/HassUI/Features/Security/,
apple/Sources/HassUI/Features/Gallery/SecurityGallery.swift → security lane (claude/project-thread-f1gx1e)
apple/Sources/HassUI/Features/{Media,CustomLights,Sprinklers}/,
apple/Sources/HassCore/Sprinklers/, HassCore/Config/{MediaPage,CustomLights,Sprinklers}Config.swift,
apple/Sources/HassUI/Features/Gallery/HomePagesGallery.swift → Home pages lane (claude/project-thread-mjn2gu)
apple/Sources/HassCore/Bedroom/,
apple/Sources/HassUI/Features/Bedroom/,
apple/Sources/HassUI/Features/Gallery/BedroomGallery.swift   → bedroom devices lane (claude/project-thread-hmhfaj)
apple/Sources/HassCore/Rooms/, apple/Sources/HassUI/Features/Rooms/,
apple/Sources/HassUI/Features/Home/HomeRoute.swift,
apple/Sources/HassUI/Features/Gallery/RoomsGallery.swift,
GlassTile kinds/wash/progress/accessory, DynamicGridLayout section layouts → rooms lane (claude/project-thread-wyoszt)
apple/Sources/HassCore/Config/HouseholdSettingsConfig.swift,
apple/Sources/HassCore/Settings/,
apple/Sources/HassUI/Features/Settings/Household/,
apple/Sources/HassUI/Features/Gallery/HouseholdSettingsGallery.swift → household settings lane (claude/project-thread-fww01h)
apple/Sources/HassCore/Feedback/, apple/Sources/HassUI/Features/Settings/Feedback/,
tools/triage/, .agents/workflow/triage-agent.md, .agents/pages/settings/feedback.md → feedback and triage lane (claude/project-thread-g7zt61)
apple/Tests/**                                             → tests for your own files only
.agents/pages/<id>/, .agents/controls/<id>/                → the lane for that page/control
.agents/** (everything else)                               → orchestrator
```

## 2. Priorities

1. **Foundation (this scaffold):** sign-in, connection lifecycle, cached entity store, Home screen.
2. **Primary tabs:** Security, Climate, Chores, Settings, at web parity, iPhone first.
3. **iPad and iPhone Duo:** flyout navigation and on-demand split per [split-view](.agents/design/apple/split-view.md).
4. **Rooms and detail pages:** room pages, Food & Recipes, Groceries, vacuums, media.
5. **Live cameras:** snapshot tiles, then HLS, then WebRTC (go2rtc).
6. **Watch app:** glanceable status and a handful of controls.
7. **Report an Issue / Feature Request:** ported from FestivalNativeApps; files into the private request repo `SFenton/fenton-hass-requests`, worked by the [triage agent](.agents/workflow/triage-agent.md) on the MacBook.

## 3. Status

| Area | State |
|---|---|
| Sign-in (login flow, MFA step, Keychain) | Verified on the live server (password sign-in, relaunch skips sign-in) on iPhone, Duo and iPad |
| Connection lifecycle and entity snapshot cache | Scaffolded; unit tests for the cache and store |
| Home | Status rail, weather, guest presence, camera snapshots, lights sheet |
| Live cameras | Viewer plays WebRTC (go2rtc), falls back to HLS, then the snapshot; tiles stay snapshots |
| Security | Alarm modes (disarm confirms), front door lock, garage doors (command state machine), hidden Vehicle tile, cameras; gallery `FENTON_GALLERY=security` |
| Climate | Page, Thermostat Hub pickers and the advanced-controls sheet (Rooms, Automation, Tracking and their detail pages); gallery `FENTON_GALLERY=climate` |
| Chores | Placeholders |
| Settings | Household topic list that splits on demand: Admin (presence overrides, auto-reset), Special Device Modes, Guest Controls, Mach-E; Home Assistant Settings opens the full-screen modal (server, account, signed-in Settings/Profile web pages, Sign Out); Vacation (pushes its own pages); To-Do not ported |
| Vacation and Solo Trip | Chooser, Vacation Mode (checklist, dates, confirm), Solo Trip (traveler, schedule, end, return, restore); `HouseholdAwayController` shared in HassCore; gallery `FENTON_GALLERY=vacation` |
| Orientation policy (iPhone portrait, Duo/iPad free) | Scaffolded with unit tests |
| Split policy (landscape regular only) | `OnDemandSplitStack` built and verified on the Mac: divider at the exact midpoint on iPad landscape, on the hinge on the unfolded Duo landscape; rotation moves the open item between pane and push; Settings is the first adopter |
| iPad / unfolded Duo flyout | Built and verified on iPad and the unfolded Duo: overlay flyout in regular width, tab bar (folded Duo: vertical bar) in compact width |
| Test tooling | XCUITest journeys + audits on iPhone/Duo/iPad (`tools/ios_uitest.sh`); 95/90 coverage gate (`tools/apple_coverage.sh`), which now measures every test bundle: repo-wide 54.2% logic / 70.5% UX on 2026-10-11 (below the bars; the gaps are HassCore connection/Keychain, Login, the Home chip sheets and RootView/AppSession) |
| Media remote (sheet, 4 remotes, Hue Sync) | Shared component + debug gallery; not yet opened from a page (Rooms/Media lanes wire it) |
| Rooms (16 pages, Quick Links, room grid) | Config-driven pages with status rail, sections, group sheets and the media remote; device sheets fall back to read-only tiles until their lanes land |
| Watch app | Target stub only |
| Report an Issue / Request a Feature | Settings → Feedback files issues (media, diagnostics, labels) in the private request repo with the person's GitHub token ([feedback](.agents/pages/settings/feedback.md)); the hourly triage agent on the MacBook works them into verified PRs labelled `Ready to Merge` ([triage-agent](.agents/workflow/triage-agent.md)) |
| Food & Recipes | Hub, Recipes grid (search, sort, filter, paging, hydration), recipe detail with grocery add; debug gallery `FENTON_GALLERY=food` |
| Inventory (6 pages, item editor, Add Item scan) | EverShelf client and models, pages, editor (sheet or split pane), AVFoundation scan; gallery `FENTON_GALLERY=inventory`; linked from Food & Recipes once it lands |
| Media, Custom Lights, Sprinklers (Home pages) | Ported; reached from the Quick Links sheet via `HomeRouteDestination` (Room pages lane); gallery pages `media-page`, `custom-lights`, `sprinklers` |
| Bedroom devices (wake light, SleepyPod bed sides) | Tiles, sheets, alarm editors, active alarm, Solo Trip routing; debug gallery `FENTON_GALLERY=bedroom`; Rooms lane places them. Verified on the Mac 2026-10-12: journeys and audits pass on iPhone, iPad (both orientations) and folded Duo; unfolded Duo portrait journeys 14/15 (one simulator crash), unfolded audits/captures not run (Device Hub unscriptable); Bedroom coverage 98.0% logic / 92.1% UX |
| Vacuums (page, sheet, Valetudo map, area editor) | `VacuumsScreen` + `VacuumSheet`; reached from Home until side navigation lands; debug gallery `FENTON_GALLERY=vacuums` |
| Room device sheets (fan, air quality, humidifier, grill) | Sheets + debug gallery `FENTON_GALLERY=room-devices`; Room pages wire them in |
| Floating actions (shared) | `FloatingActionBar` (labeled/icon actions, expandable search) + `FilterSheet`; gallery `FENTON_GALLERY=floating-actions` |
| Thermostat dial (shared control) | `ThermostatDial` + `ClimateThermostatDial`; debug gallery `FENTON_GALLERY=thermostat-dial` |

## 4. Log

- 2026-10-10: initial scaffold.
- 2026-10-11: PR #1 verified on the Mac: journeys and accessibility audits green on iPhone, Duo (folded, unfolded portrait and landscape) and iPad; 32 `swift test` tests pass. Redacted screenshots were attached to the thread.
- 2026-10-11: Lights sheet sends explicit `turn_on` / `turn_off` instead of `toggle` (Presence Based Lighting's Presence Lock reverts toggles in empty rooms), and dimmable groups get `BrightnessTile` (drag to set brightness, web `LightBrightnessCard`).
- 2026-10-11: media remote component (`.agents/patterns/media-remote.md`): config model and the four web remotes, optimistic overlay with revert timers, sheet with power, d-pad and Controls/Apps/Devices/Hue Sync tabs; unit, hosted and device journeys with audits.
- 2026-10-11: Home Assistant settings modal verified on the Mac (`claude/project-thread-4ttpvm`): the Settings web page opens signed in through the `localStorage.hassTokens` hand-off (no web login form). Settings journeys and audits pass on iPhone, Duo folded / unfolded portrait / unfolded landscape and iPad portrait / landscape; 52 `swift test` tests; new files ≥ 95% logic / ≥ 95.7% UX. `apple_coverage.sh` now measures every test bundle (repo-wide 63% / 61%, below the bars before this change too). Simulators under heavy host load crash backboardd at random; crashed journeys were re-run alone. Redacted screenshots were attached to the thread.
- 2026-10-11: shared thermostat dial (single and heat/cool range, VoiceOver-adjustable handles) with its debug gallery page.
- 2026-10-11: PR #4 verified on the Mac: dial journeys, hosted VoiceOver-adjust tests and audits green on iPhone, Duo (folded, unfolded portrait and landscape) and iPad (portrait and landscape); 69 `swift test` tests pass. Screenshots were attached to the thread.
- 2026-10-11: Food & Recipes hub, Recipes grid and recipe detail over the EverShelf recipe services (`.agents/pages/food/`), with `HassConnection.callServiceWithResponse`.
- 2026-10-11: inventory pages (All Food, Pantry, Fridge, Freezer, Spice Rack, Cabinet), item editor and Add Item scan sheet (`.agents/pages/inventory/`), on a shared `EverShelfClient` and the shared floating actions.
- 2026-10-12: inventory verified on the Mac (`claude/project-thread-2tax3x`): first compile (3 Swift 6 fixes); 530 `swift test` tests; HassCore/Inventory 98.9% and HassUI inventory 93.4% line coverage. Device fixes: editor and Add Item identifiers, `${title}${qualifier}` labels, sheet/footer contrast (ink tints, opaque FilterSheet and Add Item surfaces), wrapping empty state, AX5 Add Item buttons in the form, iPad split pane with its own header and the floating bar on the list column, bar hidden under sheets, Sort/Filter at full height, live item names redacted in shared screenshots. Journeys: iPhone all pass; Duo folded and iPad portrait/landscape pass except journeys lost to backboardd crashes under host load; Duo unfolded not run (Device Hub UI automation failed with several threads driving it). Screenshots were attached to the thread.
- 2026-10-11: Media, Custom Lights and Sprinklers pages (`claude/project-thread-mjn2gu`) Routing and Quick Links belong to the Room pages lane; whichever merges second swaps the placeholders in `HomeRouteDestination` for `MediaScreen`, `CustomLightsScreen` and `SprinklersScreen` (each `(store: connection.store, caller: connection)`; Media also takes `imageServer: connection.server`). New shared pieces: `StatusPill`, `OptionPickerSheet` + `GradientSwatch`, `BrightnessTile(onOpen:)`, `HassTokens.Tint.water`.
- 2026-10-12: Home pages (`claude/project-thread-mjn2gu`) verified on the Mac. `HomePagesJourneyTests` (14 journeys; the sprinkler audit is split per page) pass on iPhone portrait, Duo folded, Duo unfolded portrait, Duo unfolded landscape, iPad portrait and iPad landscape, with audits at real AX5. Fixes found on the way: `BrightnessTile` let pages scroll from a tile (UIKit horizontal pan on iOS 18+); contrast (opaque option picker, `Ink.action` tint because the app accent is 2.5:1, `Ink.danger`, enabled zone rows, solid pills in sheets); wrapping list-button titles; a two-row day picker on the folded Duo; Done on every sprinkler sheet level; and the journeys' AX5 relaunch, iPad orientation per pass, and the landscape `RenderedContrast` mapping (from a89cee8). Simulators under host load crash backboardd at random; crashed journeys were re-run. Redacted screenshots were attached to the thread.
- 2026-10-11: Vacuums page, vacuum sheet and Valetudo map ported (`.agents/pages/vacuums/`, `.agents/patterns/vacuum-sheet.md`, `valetudo-map.md`): status contract, queued clean with settle check, rooms and area cleaning, dock controls, while-away report; unit, hosted and device journeys with audits.
- 2026-10-11: room device sheets (`.agents/patterns/room-device-sheets.md`): bathroom fan, air quality, humidifier (mist dial on `ThermostatDial` value style, schedules over the websocket) and grill, with unit, hosted and device journeys.
- 2026-10-11: household Settings pages (`claude/project-thread-fww01h`): Admin with the presence-override and auto-reset sheets, Special Device Modes, Guest Controls and Mach-E; explicit on/off with optimistic state; `SettingsSection`, `InlineAlert` and `SelectableOptionRow` in HassDesign; feature-local read-only `GlassStateTile`; gallery page `FENTON_GALLERY=household-settings`.
- 2026-10-11: app navigation: regular-width overlay flyout (`App/Shell/`), `OnDemandSplitStack` with hinge-aware geometry, Settings list/detail split.
- 2026-10-11: PR #3 verified on the Mac. Fixed: the split never turning off after rotating to portrait (it measured its own fixed-width panes); the hinge not being read (read in `onGeometryChange`, inactive division while flat); content under the flyout still reachable by VoiceOver (UIKit tab controller hidden too); the full-window scrim winning the accessibility hit test over the rows; white-on-accent selected row (2.5:1); the edge strip eating taps, then the edge swipe also activating the control under it (now a UIKit screen-edge pan); a `DynamicGridLayout` crash on unbounded widths; the coverage script measuring one of three bundles. Redacted screenshots were attached to the thread.
- 2026-10-11 (after merging #4/#7): known failure not from PR #3: the four `MediaRemoteJourneyTests` tab audits fail in iPad landscape on clean `origin/main` (74c98f2) exactly as on the navigation branch ('Last call: None' 1.2:1, toggle 'On' 1.0:1). The audited screenshot is a portrait-shaped capture of a landscape screen, so `RenderedContrast` samples the wrong pixels. Owner: the media-remote lane. Resolved by #11's `RenderedContrast` change: all four pass on iPad after the 2026-10-12 merge.
- 2026-10-12: merged #11 into the navigation branch: the Settings split now opens the household pages (`HouseholdSettingsPage`) in place of the placeholder topics.
- 2026-10-12 (after merging #11): known failures not from PR #3, reproduced on clean `origin/main` (e75b80c) on iPad and the folded iPhone Duo: `HouseholdSettingsJourneyTests.testPresenceOverrideSetsTheRoomMode` and `testUnavailableEntitiesDisableTheirControls` expect an unavailable presence room to be disabled, but `AdminSettingsContent` deliberately keeps it openable ("Unavailable rooms stay openable"); `testPagesPassAccessibilityAudit` fails on iPad and the folded Duo with text that has no element behind the form sheet once a presence detail is pushed (the audit's sheet exception expects Done in the bar). Owner: the household-settings lane.
- 2026-10-12: household journey fixes (`claude/project-thread-fww01h`): the presence journeys expect unavailable rooms to open with disabled choices; the presence detail carries the sheet's Done (closes the sheet from any depth, and satisfies the audit's sheet exception); the relay warning journey reveals the relay tile before tapping it (flaky on the folded Duo).
- 2026-10-12: Climate page (`claude/climate-page`): Whole Home dial (eco-away while away, range fan-out to the eleven rooms), Thermostat Hub mode and fan pickers, away notice, Automatic Thermostat warning, open contacts, and the Thermostat · Advanced Controls sheet (Rooms, Automation, Tracking, room, Predictive Comfort, Eco option and tracking pages). Journeys and audits pass on iPhone (light and dark), Duo folded, unfolded landscape and unfolded portrait, and iPad portrait and landscape; backboardd crashes under host load were rerun alone. New Climate files 100% logic, 91.5–98.4% UX. Shared `SheetTabPicker`; Device Hub's own window buttons (device_hub_ax select-row + press) set Duo poses when Xcode's menu route fails. Screenshots were attached to the thread.
- 2026-10-11: room pages (`.agents/pages/rooms/`): all 16 rooms from `roomPages.ts`, Quick Links, the ranked room grid and the `HomeRoute` registry; `GlassTile` gains `.selection` / `.state` kinds, wash, progress and a trailing accessory.
- 2026-10-12: room pages merged with main (room device sheets #12, Vacuums #16): room cards open `BathroomFanSheet`, `AirPurifierSheet`, `HumidifierSheet`, `GrillSheet` and `VacuumSheet` through `RoomDeviceModal`; the bathroom fan tile gets Lock and Power accessories on a shared `BathroomFanController` (explicit targets); `HomeRoute.vacuums` → `VacuumsScreen` and the temporary Home link is gone. Mac fixes on the way: Quick Links / room-grid tiles ignored taps (tile inside a Button label with hit testing off), two-column sections reflow at AX5, GlassTile icons hidden from VoiceOver, RenderedContrast measures the glyph tail, host screenshots wait 3 min.
- 2026-10-12: room pages merged with main again (Media, Custom Lights and Sprinklers #20, Bedroom, Climate): `HomeRoute` opens `MediaScreen`, `CustomLightsScreen` and `SprinklersScreen` on the app's connection (placeholders in the gallery); Quick Links reads `SprinklersConfig.visibilityEntityId`; one `HouseholdResident` (Bedroom's), with the room cards' `haUserId` / `forUser` as an extension.
- 2026-10-11: shared floating action bar and filter sheet (`.agents/patterns/floating-actions.md`) for Chores, Groceries, To-Do, Recipes and Inventory.
- 2026-10-11: Vacation and Solo Trip pages (`claude/project-thread-d1pa5r`): `HouseholdAwayController` (return-response script calls, revision floor, timeout), `VacationModeController`, `SoloTripController`, shared `ScheduleDateFields` and `InfoBox`, Settings → Vacation, fixture gallery and journeys.
- 2026-10-13: merged main into the Vacation branch: Vacation stays a pushing row above the household topics (follow-up: make it a split topic). Mac runs before the merge: iPhone journeys, audits and screenshots passed in full; iPad (portrait and landscape) and folded Duo fixes were pushed from those runs; unfolded Duo runs skipped (Stephen, 2026-10-13: merge without them; run once a Duo can unfold). Swift was not rebuilt after the merge.
- 2026-10-13: Report an Issue and Request a Feature in Settings (`claude/project-thread-g7zt61`): port of FestivalNativeApps' feedback form that files straight into the private request repo `SFenton/fenton-hass-requests` (fine-grained token in iCloud Keychain, media stripped of location and fitted to 10 MB, diagnostics), and the MacBook triage agent (`tools/triage/hass_triage.py`, hourly launchd job) that works each request into a verified PR labelled `Ready to Merge`. Nothing on the Mac merges (owner: coordinator merges).
