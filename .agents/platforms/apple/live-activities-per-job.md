# Live Activities, one per job (spec v2)

> **What:** how S+H shows each running household job, and each device problem, as its own Live Activity, kept current by Home Assistant while the app is closed. It covers the wire contract, the `fenton_push` job engine, every job kind and problem code, stop and cancel flows, slots and ordering, the views, tests and the lane plan. **Read when:** building or changing Live Activities, the widget extension, the `fenton_push` engine, or the Home Assistant side.

Status: spec, owner-approved design (Stephen, 2026-10-17), not built. It **supersedes** [live-activities.md](live-activities.md) §1 ("one activity, not many"), §3 (content state v1), §4 (presentation) and §6 (engine rules), and **retires** [live-activities-ha-automations.md](live-activities-ha-automations.md) once the engine ships. Everything else in those files (the token plumbing in §0, privacy, the Phase 1 targets) still holds.

Design source: the canvas **S+H Live Activity** (`https://claude.ai/artifact/ToY74UpYgCganecAfGTg3x`), boards 5 to 8: "Two jobs" and "Four jobs" stacks, "Corner mark follows your app icon", "Vacuum, one room per card", "Expanded island on every camera width", "Problem cards". The boards are the visual contract; this file is the behavioural one.

## 0. Decisions (owner, 2026-10-17)

1. **One Live Activity per job**, not one aggregate activity with a pager. Each card has the job's full name and one big value. There is no subtitle line for fans, the dishwasher or laundry.
   - **HIG departure:** the HIG prefers one activity that follows several events. The owner chose separate cards because each gets its own button, ends by itself and needs no paging. Recorded here; the slot cap in §6 keeps us inside the per-app limit.
2. **No auto-rotation.** Activities run no code, so a 10 s carousel is impossible. Relevance scores decide which card the Dynamic Island shows.
3. **The corner mark** is the house and heart only, 40 pt, with no tile. It is tinted with the app icon picked in Settings → Appearance → App Icon, and falls back to Navy + Sky.
4. **Buttons say Stop.** For a fan, Stop turns the fan off; it does not just cancel the timer.
5. **Vacuums show one room at a time.** A card ends when its room finishes, and a new card starts when the next room starts. There are no room counts and no map.
6. **One problem card design for every device.** The device name is the title. Red means it stopped and needs you (with sound); amber means it carries on but needs attention (silent). **There is no offline card.**
7. **Laundry has no buttons.** People swipe the card away.

## 1. What failed in Phase 1 (2026-10-17)

| Symptom | Root cause | Fix (where) |
|---|---|---|
| A card stays on "Stopping…" until the app opens | `script.fenton_home_activity_push` failed on every run. `jobs` is rendered with `tojson`, HA's native typing turns it back into a list, and `jobs \| from_json` then raises. So no start, update or end ever left Home Assistant. Traces: 16:31:31, 16:32:50 and 16:32:53 PDT, all `from_json got invalid input` | Fixed in `/config/packages/fenton_live_activity.yaml` at 17:27 PDT (backup `*.from-json-fix-20261017.bak`); the next run finished. The same bug is fixed in [live-activities-ha-automations.md](live-activities-ha-automations.md) |
| …and nothing ever cleared it | The optimistic `.stopping` update sets `staleDate: nil` and the app has no timeout (`HomeActivityActionHandler.swift:54,62`), so a lost confirmation leaves it there forever | §7: an optimistic state always carries a stale date, and a stale pending state gives the button back |
| The expanded-island timer is cut off at the top right | `ActivityTrailing(width: 96)` caps an `H:MM:SS` title3 countdown at 96 pt, beside the camera | §8: only the ring and a 22 pt timer sit beside the camera, with no fixed frames; the name and buttons go below the camera |
| The app and Home Assistant both write the activity while the app is open | `HomeActivityDirector` updates from `EntityStore` with no hand-off (spec §0 decision 3 said it "must yield", which was never built) | §2: the engine is the only writer of content. The app writes only the optimistic state |

## 2. Architecture

```
Home Assistant (always on)
  device entities ──state changes──▶ fenton_push job engine (live_jobs.py, new)
                                       adapters: fan, dishwasher, dryer, washer, vacuum, problem
                                       slots, relevance, coalescing, control map, timestamps
                                       │  per job: notify.mobile_app_<device>_fenton
                                       │  {tag: "job.<id>", live_update: true, fenton_activity: {v: 2, …}}
                                       ▼
                                     mobile_app (core 2026.10.1): start | update | end per tag
                                       ▼
                                     fenton_push relay (payload.py) ─▶ APNs liveactivity
iPhone: ActivityKit renders · button → LiveActivityIntent (app process)
        → optimistic local update + webhook fire_event fenton_live_activity_action {tag, job, control}
        → engine calls the service, waits for the state, pushes the result
```

Rules:
- **The engine is the only writer of job content.** Job derivation lives in Python inside `fenton_push`, with unit tests, not in YAML templates. The Phase 1 YAML package is what broke, and nothing tested it.
- **The app writes only three things:**
  1. the optimistic pending state after a button;
  2. `endAll()` on sign-out;
  3. token reports.
- **The foreground director and `HomeJobDeriver` are deleted.**
  - The app no longer starts activities locally. iOS 17.0 and 17.1 lose Live Activities; push-to-start needs 17.2. The owner runs iOS 27.
- **Tags.** One tag per job, `job.<job_id>`. Examples: `job.fan.guest`, `job.fan.master`, `job.dishwasher`, `job.dryer`, `job.washer`, `job.vacuum.main_floor`, `job.vacuum.music_room`, `job.vacuum.theater_room`.
  - A device's problem state rides on **the same tag**: the card turns into a problem card and back. A problem with no running job, for example "Dust bag full" while docked, starts that device's tag on its own.
  - So a device never has two cards.
- **One attributes type.** `HomeActivityAttributes` stays. Core holds one push-to-start token per registration (`app_data.start_live_activity_token`), and the type name is the wire `attributes-type`. Renaming it would orphan the token.

## 3. Wire contract v2

### Attributes (static, sent on start)

All new keys decode with defaults, so Phase 1 pushes still decode.

| Key | Type | Example | Notes |
|---|---|---|---|
| `tag` | String | `job.vacuum.main_floor` | |
| `title` | String | `Main Floor Vacuum` | The device. It never changes for the life of the activity |
| `kind` | String | `fan` · `dishwasher` · `dryer` · `washer` · `vacuum` · `problem` · `generic` | `home` is still decoded (Phase 1) |
| `symbol` | String | `fan` | Glyph id from the app's own set (§8), not an SF Symbol name on the wire |
| `tint` | String | `air` · `cleaning` · `water` | A `ColorFamily` raw value |

### Content state v2 (`aps.content-state`)

Explicit `CodingKeys` with snake_case keys. Times are Unix seconds as doubles (the 2001-epoch trap still applies).

```json
{"v": 2,
 "phase": "running",
 "headline": "Vacuuming Kitchen",
 "value": {"kind": "countup", "start_ts": 1792281000},
 "progress": null,
 "controls": [{"id": "pause", "title": "Pause"}, {"id": "dock", "title": "Dock", "role": "secondary"}],
 "problem": null,
 "pending": null,
 "url": "/sfenton-react-dash/home?path=vacuums"}
```

| Key | Type | Meaning |
|---|---|---|
| `v` | Int | `2`. A `1` payload decodes by taking its focus job, for one release |
| `phase` | `running` `paused` `waiting` `problem` `done` | `waiting` covers a delayed start ("Starts 5:10 PM") |
| `headline` | String? | Overrides the title line on the card. Vacuums use it ("Vacuuming Kitchen"); everything else leaves it nil and shows the attribute `title` |
| `value.kind` | `countdown` · `countup` · `percent` · `text` | `countdown` needs `end_ts` (and `start_ts` for the ring). `countup` needs `start_ts` and an optional `paused_elapsed_s`, which shows a frozen time while paused. `percent` needs `progress`. `text` needs `text` (≤ 16 characters, e.g. "Done") |
| `value.estimated` | Bool | The dryer's learned ETA. It still shows a countdown; the VoiceOver label says "about" |
| `progress` | Double? 0…1 | Drives the ring when there is no time range |
| `controls` | [≤ 2] `{id, title, role}` | `role`: `primary` (white pill) or `secondary` (dark pill). The first control is primary |
| `problem` | `{severity, code, icon, problem, message, chips[≤2]}`? | Present ⇔ `phase == problem`. `severity` is `critical` or `warning`. `icon` is from the problem glyph set (§5). Strings are already worded by the engine |
| `pending` | `{control, label, since_ts}`? | Written **only by the app** (§7). The engine never sends it, so any push clears it |
| `url` | String? | Tap target, mapped by `ActivityDeepLink` |

Budget: the whole payload must be ≤ 4 KB. Strings are capped: title 32, headline 32, problem 40, message 90, chip 20 characters. The relay refuses anything larger, and the views truncate.

### Fixtures

The relay lane generates `tests/fixtures/live2-*.apns` (fan start, fan stop end, dishwasher percent, dryer estimated, vacuum count-up, vacuum paused, problem critical, problem warning, unknown error, unmapped error, v1 compatibility). They are mirrored into `tools/push_fixtures/`, and the app's `RelayFixtureTests` decode every one. **The app lane hand-writes the same fixtures from this table first**, and review diffs the two sets.

## 4. Jobs

Times are local. "End now" means `clear_notification`, which the relay sends as `dismissal-date = now` (immediate removal).

| Job | Starts when | Card | Updates on | Ends when | Controls → service |
|---|---|---|---|---|---|
| **Bathroom fan** (`fan.guest`, `fan.master`) | `input_boolean.<r>_bathroom_fan_timer_pending` turns on and `input_datetime.<r>_bathroom_fan_timer_ends_at` is in the future (`ends_at` is stale after a cancel, so check both) | "Guest Bath Fan", countdown to `ends_at`; ring from pending `last_changed` | `ends_at` moves by more than 30 s (timer extended) | pending turns off (expired, cancelled, fan turned off anywhere) → end now | **Stop** → `script.<r>_bathroom_fan_command {command: power, target_power: off}`. The lane confirms in `scripts.yaml` that `power off` also clears the timer; if not, call `timer_cancel` and then `power off` |
| **Dishwasher** (`dishwasher`) | `sensor.dishwasher_operation_state` → `run` (or `delayedstart`, which is `waiting` with "Starts h:mm") | "Dishwasher", countdown to `sensor.dishwasher_program_finish_time`; if that is unavailable, `percent` from `sensor.dishwasher_program_progress` | finish time moves by more than 60 s; progress +5 points, at most every 5 min, priority 5; `pause` ↔ `run` | `finished` → end with `value: text "Clean"` and a 15 min linger (open question 1); `ready` / `inactive` / `aborting` → end now | **Stop** → `button.press button.dishwasher_stop_program` (only while `binary_sensor.dishwasher_remote_control` is on; otherwise no button). While `pause`: **Resume** → `button.dishwasher_resume_program`. No Pause (Home Connect has no pause entity) |
| **Dryer** (`dryer`) | `input_boolean.dryer_started_helper` → on (5 min after vibration starts, so `start_ts` = on − 300 s) | "Dryer", countdown to start + learned median (`value.estimated`). Past the estimate it switches to `countup` from the start | the estimate passes | helper → off → end now (the household "Dryer done" notification still goes out, so the card does not alert) | none |
| **Washer** (`washer`) | **Deferred.** The vibration sensor only catches the spin (5 to 9 min spells), so it can't tell when a wash started. It needs a power-monitoring plug (open question 2) | | | | none |
| **Vacuum, Main Floor** (`vacuum.main_floor`) | `sensor.main_floor_vacuum_coordinator_current_room` gets a `room_id` with phase `cleaning` (or `resumed_cleaning`) | headline `{Vacuuming\|Mopping\|Cleaning} {room_name}`. The verb comes from `vacuum_only`, else `select.valetudo_exaltedsneakydeer_mode` (`vacuum` → Vacuuming, `mop` → Mopping, `vacuum_and_mop` → Cleaning). Count-up from `start_confirmed_at`. `room_name` comes from the matching `sensor.main_floor_vacuum_coordinator_<room>_last_cleaned` attribute | vacuum `paused` ↔ `cleaning` (with `paused_elapsed_s`); problem raised or cleared | `room_id` changes or clears → end now; a new room → start again (same tag; core removed the token on the end, so this is a fresh push-to-start) | **Pause** / **Resume** and **Dock** → while `binary_sensor.main_floor_vacuum_coordinator_auto_cleaning` is on, use `valetudo_vacuum_coordinator.set_paused` and `cancel_session`; otherwise `vacuum.pause` / `vacuum.start` / `vacuum.return_to_base` (§7) |
| **Vacuum, manual runs** (any robot, no coordinator session) | vacuum → `cleaning` with no coordinator session | `sensor.valetudo_<id>_status_flag`: `segment` → "Vacuuming {estimated segment}"; `zone` → "Cleaning {floor} area" (drawn area); `spot` → "Spot cleaning"; `none` → "Cleaning {floor}". Count-up from the state change | segment changes (ends and restarts, as above), pause, problem | `returning` / `docked` / `idle` → end now | as above, with plain `vacuum.*` services |
| **Problem** (any device tag) | §5 | §5 | issue changes | issue clears → back to the job content if the job still runs, else end now | §5 |

Other candidates found (not in this phase; owner question 5): EV charging (FordPass `elvehcharging.estimatedEndTime`, no HA stop control), the Traeger cook timer (`sensor.d8478fa2ad0a_cook_timer_remaining`, grill offline today), sprinklers (B-hyve valves, `zone_name` attributes don't match entity names), hot flash timers (15 min, bedtime only), and media sleep timers (no end time).

**Dryer learner (HA side, §10).** This is a trigger-based template sensor `sensor.dryer_cycle_minutes`. On each helper on→off it appends the run's minutes to a list of the last 10 runs in its attributes, and its state is their median. Until 3 runs are recorded, the card uses `countup` with no estimate.

## 5. Problem cards

Source: the coordinator's `sensor.<floor>_vacuum_status` `current_issue` (`code`, `status`, `since`) for Main Floor. For robots without a coordinator, the engine runs the same mapping on `sensor.valetudo_<id>_error` using `issue_code_for_raw`'s rules (the known table, then `unknown error N` → `vendor.unknown_error_N`, else `unmapped.<slug>`). For the dishwasher it uses `operation_state` `actionrequired` / `error`.

Wording lives in the engine (`problems.py`), so new wording ships with a relay update, not an app release.

| Code | Severity | Icon | Problem | Message | Buttons |
|---|---|---|---|---|---|
| `navigation.stuck` | critical | alert | Stuck in {room} | Move it somewhere flat, then tap Resume. | Resume · Dock |
| `navigation.target_unreachable` | critical | door | Can't reach {room} | A door may be closed. Open it, then tap Resume. | Resume · Dock |
| `navigation.dock_unreachable` | critical | dock | Can't get back to the dock | Clear the way to the dock or carry it there. | Try Again (→ return to base) |
| `navigation.ramp_hazard` (error 95) | critical | edge | Stopped at a drop or ramp | Move it away from the edge, then tap Resume. | Resume · Dock |
| `maintenance.main_brush_jammed` | critical | brush | Main brush jammed | Turn it over, clear the brush, then tap Resume. | Resume · Dock |
| `maintenance.side_brush_jammed` | critical | brush | Side brush jammed | Untangle the side brush, then tap Resume. | Resume · Dock |
| `power.critical_battery` (error 75) | critical | battery | Battery critically low | Carry it to the dock to charge. | none |
| `power.low_battery` | warning | battery | Battery low | Heading to the dock. It finishes {room} after charging. | none |
| `mop.clean_water_empty` | warning | water | Clean water tank empty | Refill the clean water tank on the dock, then tap Resume. | Resume |
| `mop.dirty_water_unavailable` | warning | waste | Wastewater tank full or missing | Empty the wastewater tank and seat it firmly. | Resume |
| `mop.attachment_missing` (error 120) | warning | mop | Mop pads missing | Attach the mop pads, or it vacuums only. | Vacuum Only (→ mode `vacuum`, then resume) |
| vacuum-only fallback (`input_text.<floor>_vacuum_error_message` while the fallback helper is on) | warning | mop | Vacuuming only | Mopping isn't available. Check the mop attachment, water tanks and pads. | none |
| `dock.cover_open` | warning | bag | Dock cover open | Check the dust bag is in, then close the cover. | none |
| `dock.dustbag_blocked` | warning | bag | Dust bag full | Replace the dust bag in the dock. | none |
| `vendor.unknown_error_N` | critical | question | Stopped with an error | Check the robot, then tap Resume. Chips: "Error N", "Since h:mm" | Resume · Dock |
| `unmapped.*` | critical | question | Stopped with an error | The robot says "{raw text}". Check it, then tap Resume. Chips: "Not recognised yet", "Since h:mm" | Resume · Dock |
| dishwasher `actionrequired` | warning | door_dish | Needs attention | Check the dishwasher's display. (Home Connect gives no reason; refine if an event entity appears) | none |
| dishwasher `error` | critical | question | Stopped with an error | Check the dishwasher's display. | none |
| unavailable / offline | none | | | **No card** (owner). An activity already running ends | |

Rules:
- **Alerts.** A critical problem alerts with sound. The engine sends `live_alert: true` on the update that turns the card red, or, when the problem starts a new activity, a start followed by an alerting update 2 s later. The relay's start alert is silent; §9 adds a start-sound option and then the follow-up goes away. Warnings never alert. Clearing never alerts.
- **Household notifications stay.** The existing `Vacuum Error Notifications` (to `notify.household`, with Donetick tasks) keeps running, because it reaches people without S+H. The Live Activity is the owner's live view. If that turns out to double-alert on the owner's phone, suppress the problem *alert* (not the card) for devices that have an active activity (open question 6).
- **Unknown text** is quoted as received, capped at 60 characters, and the engine logs `fenton_push.problem_unmapped` once per text so the mapping can be added.
- `power.low_battery` while returning keeps the job card's tag. When the robot docks to charge mid-session, the card stays as a warning until cleaning resumes (then it is the job card again) or the session ends.

## 6. Slots, ordering and budget

- **Cap: 5 activities per device**, the observed per-app limit (`targetMaximumExceeded`); Apple publishes no number. The engine keeps **4 for jobs and 1 for a problem**.
  - A fifth job waits in the engine's queue and starts when a slot frees.
  - A problem when all 5 are used ends the job with the lowest relevance (the latest-ending one) and takes its slot.
- **Relevance score** (`data.relevance_score`, re-sent on every update):
  - critical problem 100;
  - warning 90;
  - jobs `80 − min(minutes left, 60) / 2` (so 50 to 80, where sooner is higher);
  - count-up jobs 55;
  - done/linger 10.

  The Dynamic Island shows the highest; the Lock Screen orders by it.
- **Priority.** 10 for start, end, alerts and control confirmations; 5 for everything else (the relay's rule already). Don't set `NSSupportsLiveActivitiesFrequentUpdates`. Running timers tick on their own, so pushes happen only on real changes.
- **Coalescing.** At most one push per tag per 2 s. A burst collapses to the latest state. The relay stamps strictly increasing timestamps per tag (§7).
- **8-hour limit.** No job here runs that long. The engine ends any activity at 7 h 45 min, and restarts it if the job is still going.
- **Person's dismissal.** On `fenton_live_activity_dismissed {tag}` the engine marks that tag dismissed until the job ends; it doesn't restart a card someone swiped away. A **problem** that becomes critical after a dismissal does start again.

## 7. Buttons, stop and cancel

Sequence for every control:

1. **Intent (app process, `JobControlIntent(tag, control)`).**
   - Find the activity by tag.
   - Write `pending = {control, label, since_ts: floor(now)}` with `staleDate = now + 20 s` and `timestamp = floor(now)`, in whole seconds, never in the future. `label` is "Stopping…", "Pausing…", "Resuming…" or "Docking…".
   - The view swaps the controls for the label.
   - Fire `fenton_live_activity_action {tag, job, control}` on the registration webhook, with a 10 s timeout.
   - On a webhook failure, write the previous content back with no `pending` and a `notice` "Couldn't reach Home".
2. **Engine.**
   - Check that the job still offers that control and that the event's user (context) is allowed.
   - Call the service from the control map (§4, §5). The map lives in the engine, never on the phone.
   - Then wait up to 15 s for the expected state (fan pending off; dishwasher `ready`/`inactive`; vacuum `paused`/`cleaning`/`returning`).
3. **Confirm.**
   - **Stop and Dock** succeed → end now. The card disappears; that removal is the confirmation.
   - **Pause / Resume** → an update with the new phase.
   - **Timeout or service error** → an update with the real current state (controls back) and `notice: "Couldn't {verb}. Try again."`, shown in place of the value for that update only.
4. **If no push arrives at all** (the network is lost after the tap):
   - the stale date passes, and the view sees `context.isStale && pending != nil`;
   - it shows the controls again with a small "Not confirmed" line.
   - A pending state can never stick.
5. **Timestamps.** ActivityKit drops an update whose timestamp is older than the current content.
   - The intent stamps `floor(now)`.
   - The relay stamps `max(ceil(time.time()), last_ts[tag] + 1)`, so a confirmation is always newer than the optimistic write and pushes for one tag never tie.
   - Home Assistant's host is NTP-synced; the engine logs a warning if `now − last_changed` of a state it reacts to is negative (clock skew).
6. **Stop from elsewhere** (the wall switch, the dishwasher panel, the vacuum app) takes the same path from step 3: the state change ends or updates the card. There is no separate "cancellation notification". The card leaving is the signal, and the household notifications (laundry done, dishwasher clean, vacuum complete or stopped early) stay as they are.

## 8. Presentation

All from the canvas boards; Lock Screen first.

- **Job card** (fan, dishwasher, dryer):
  - a 64 pt progress ring with the job glyph;
  - the title (17 pt semibold, one line, tail truncation);
  - the big value (38 pt semibold, monospaced digits);
  - the primary control bottom-right;
  - the corner mark top-right.
  - Height ≤ 160 pt at default text size; at AX sizes, the value wraps under the title and the controls stack.
- **Vacuum card.** The same, with `headline` as the title line and a steady full ring (no per-room progress). Paused dims the ring and shows the frozen time at 55% white.
- **Problem card.** It has its own layout, not the job layout:
  - a severity-tinted background (critical red gradient, warning amber) with a matching hairline border;
  - a 44 pt solid severity circle with the problem glyph;
  - the device title, the problem line in the severity's light tint, the instruction in body text, and optional chips;
  - buttons bottom-right;
  - the corner mark.
  - VoiceOver reads "Main Floor Vacuum, needs help: Stuck in Kitchen. Move it somewhere flat, then tap Resume."
- **Corner mark.** Draw the house-and-heart `Shape` from `AppIconArtwork` (HassDesign), 40 pt, tinted with the foreground colour of the chosen `AppIconChoice`.
  - The heart's knock-out uses the card's background colour (problem cards pass their tint).
  - The app writes the choice's raw value to `UserDefaults(suiteName: "group.com.sfenton.home")` key `appIconChoice` at launch and on change. The widget only reads it, falling back to `navySky`. A change shows on the next update.
- **Dynamic Island, expanded.**
  - **Leading region** (beside the camera): the 34 pt ring or the severity circle only.
  - **Trailing region** (beside the camera): the value at 22 pt semibold, monospaced, `lineLimit(1)`, `minimumScaleFactor(0.8)`, **no fixed `frame(width:)`**. Problems show "Needs help" or "Attention" here.
  - **Bottom region:** the title or headline (17 pt, one line, tail truncation) and up to 2 controls.
  - **Center region:** empty.
  - The system sizes the regions for each phone's camera, so there is no device check.
- **Compact:** leading is the ring with the glyph (26 pt); trailing is the value (15 pt, monospaced); a problem shows the severity circle and a one-word label ("Stuck", "Refill water").
- **Minimal:** the ring only, which fits a 28 pt circle.
- **Limited width:** when `isDynamicIslandLimitedInWidth` is set (iOS 27 SDK, behind `#available`), show compact leading only.
- **Always-On / `isLuminanceReduced`:** hide the ring track and keep the value.
- **StandBy** scales the Lock Screen view; drop the corner mark when `isActivityFullscreen`.
- **Watch `.small`:** the glyph, title and value; no controls.
- **Accessibility.** Each card is one element plus its buttons. Controls read "Stop Guest Bath Fan", "Pause Main Floor Vacuum". Count-up values read "running for 12 minutes". Test at AX5 on iPhone, iPhone Duo and iPad, with 44 pt targets.

## 9. `fenton_push` changes (repo `SFenton/ha-fenton-push`)

1. **`live_jobs.py` engine** (the Phase 2 engine in live-activities.md §7, re-scoped per job):
   - adapters per job kind (§4), each a pure function `(states) -> JobState | None` with unit tests on recorded state snapshots;
   - the slot manager and relevance (§6);
   - coalescing;
   - the control map and the `fenton_live_activity_action` / `_dismissed` listeners (§7);
   - the wait-for-state confirmation;
   - fan-out per registration through `notify.mobile_app_*` (core keeps owning tokens);
   - `sensor.fenton_live_jobs` (per-tag state, for debugging).
   - Configured in the integration's options: which jobs are on and which registrations get cards (open question 4).
2. **`problems.py`.** The §5 table, the raw-text fallback, and the `problem_unmapped` log.
3. **`payload.py` / `live.py`.**
   - Accept content state v2 (validate keys, caps and 4 KB).
   - Put `kind`, `symbol` and `tint` into `attributes` on start.
   - `live_alert` on a **start** adds `sound: default`.
   - Strictly increasing per-tag timestamps (§7.5).
   - Keep v1 for one release.
4. **Dead token recovery.** Core turns a start for a tag that still has a stored (dead) token into an update. APNs answers 410, and core does not remove the token, so the tag can't restart until the token expires (8 h).
   - On a 410 for `liveactivity`, the relay removes that tag's token through core's `mobile_app.live_activity` store helper. It is guarded by an import check and a version check, and logs if core changes.
   - The engine then retries once as a start.
   - Also open an upstream issue so core drops the token on 410 itself.
5. **Tests.**
   - pytest for adapters, problems, slots, timestamps and the control map;
   - HA tests through `mobile_app` with a stored token;
   - fixtures `live2-*.apns` (§3).

## 10. Home Assistant config (planner, with the owner's standing approval; back up first)

- After the engine ships and is verified, remove `/config/packages/fenton_live_activity.yaml`: the engine replaces its script and automations. Back it up first.
- Add `sensor.dryer_cycle_minutes` (§4) in a new package `fenton_dryer_learner.yaml`.
- Leave every household notification automation as it is (dishwasher clean, rinse aid, laundry done, vacuum complete and errors).
- Validate with `ha core check`; reload template entities. No service call against the house during tests; the engine's unit tests use recorded snapshots.

## 11. App changes

| Area | Change |
|---|---|
| `FentonActivityModel` | `HomeActivityAttributes` gains `symbol` and `tint` (defaults). Content state v2 replaces `jobs[]`/`focus`/pager with the single-job fields in §3; v1 decodes by taking the focus job. Delete `HomeActivityState.pager`, `fitted()`'s multi-job logic, `LiveActivityAction.focus`. Caps per §3 |
| `FentonActivityViews` | New `JobCardView`, `ProblemCardView`, `CornerMark`, island regions per §8. Delete `ActivityPager`, `ActivityFocusLine`, the multi-row Lock Screen, `ActivityTrailing`'s fixed widths |
| `HassCore/LiveActivity` | Delete `HomeActivityDirector`, `HomeActivityPlanner`, `HomeJobDeriver`. `HomeActivityActionHandler` → pending per §7 (stale date, timestamp, notice). `LiveActivityTokenReporter` stays, and must send `live_activity_dismissed` for **every** local end as well as a swipe-away |
| `HassUI/App/LiveActivity` | `LiveActivityCoordinator` keeps token reporting and `endAll` on sign-out only |
| Settings | Write `appIconChoice` to the app group (`AppIconPickerModel` on apply, and at launch) |
| Intents | Drop `FocusJobIntent`. `JobControlIntent(tag, control)` |
| Gallery | `FENTON_GALLERY=live-activity` scenarios for every canvas card: fan, dishwasher countdown and percent, dryer estimated, vacuum running/mopping/drawn area/paused, all 18 problem rows (§5), pending, pending-stale, notice, 4-card stack |

## 12. Tests and verification

- **Unit tests:**
  - every fixture decodes;
  - v1 → v2;
  - the value-kind rules;
  - pending + stale → controls back;
  - truncation caps;
  - the timestamp floor;
  - the problem table renders every icon.
- **UX and accessibility** (iPhone, iPhone Duo, iPad) through the gallery:
  - every card ≤ 160 pt at default size;
  - names and roles;
  - 44 pt targets;
  - AX5 layout;
  - reading order;
  - the expanded-island stand-in at the smallest and largest widths with an `H:MM:SS` value, asserting nothing is clipped (the trailing text's frame fits inside its region).
- **Coverage** ≥ 95% logic / 95% UX (`tools/apple_coverage.sh`).
- **Relay:** pytest green, plus HA's `ha core check` after the HACS update.
- **Device checks (owner's phone; planner deploys):**
  1. Fan timer from the dashboard with the app closed → card. Stop → card gone, fan off.
  2. Dishwasher run → countdown; Stop → card gone.
  3. Main Floor room clean → card per room; Pause/Resume/Dock.
  4. A forced problem: lift the robot → red card with sound; set it down + Resume → back to the job card.
  5. Airplane mode, then tap Stop → "Stopping…", then "Not confirmed" with the button back after about 20 s.
  6. Five jobs → the cap holds.
  7. Watch Smart Stack.

## 13. Lanes and order

| Lane | Repo | Scope | Depends on |
|---|---|---|---|
| A, engine and relay (Sonnet) | `SFenton/ha-fenton-push` | §9, fixtures | this spec |
| B, app (Sonnet) | this repo | §11, §12; hand-written fixtures first | this spec (runs in parallel with A) |
| C, HA config (planner) | owner's `/config` | §10 | A deployed through HACS |

Merge order: B can merge first (v1 stays decodable). Deploy B to the phone. Then deploy A through HACS, run the device checks, then C. Review diffs A's generated fixtures against B's hand-written ones before either merges.

## 14. Open questions (owner)

1. **Dishwasher finished:** keep a 15 min "Clean" card, or remove it at once? The household "Dishwasher clean" notification already goes out.
2. **Washer:** skip it until a power-monitoring plug is added, or show a card only during the spin?
3. **Dryer estimate:** fine to learn from the last 10 runs, and count up until 3 runs are recorded?
4. **Who gets cards:** only your phone, or every S+H install (each person's own registrations)?
5. **More jobs later:** EV charging, grill cook timer, sprinklers, hot flash. Which, if any?
6. **Problem alerts** on your phone would double up with the household vacuum error notification. Keep both, or let the card's alert replace the notification for you?
