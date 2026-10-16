# Presence inventory

> **What:** what Home Assistant does with presence today, so the native app's `device_tracker` is added without surprises. **Read when:** linking the app's tracker to a person, changing `HassCore/Location`, or planning the shadow-to-live switch in [location.md](location.md).

Read-only inventory of Home Assistant presence, taken 2026-10-15 for the Location lane. Source: the live REST and websocket APIs (states, entity and device registries, person, zone, automation and script configs) plus read-only greps of `/config` YAML and `custom_components`. Nothing was changed. Home coordinates are left out on purpose.

## Zones

| Zone | Radius | Passive | Used by |
|---|---|---|---|
| `zone.home` | 33 m | no | Home/Away, `group.household_presence`, most automations below |
| `zone.stephen_office` | 100 m | no | Stephen's person state shows "Stephen Office" while inside |
| `zone.steph_office` | 100 m | no | Same for Stephanie |
| `zone.costco` | 217 m | yes | Location-Based Grocery Notifications (zone trigger) |
| `zone.trader_joe_s_qfc` | 76 m | yes | Same |
| `zone.gucci_qfc` | 86 m | yes | Same |

Passive zones do not set a tracker's state; they only produce zone triggers and `in_zones`. The native `ZonePlanner` skips passive zones, so the store zones are not monitored by the app's regions and the grocery automation keeps relying on the official app. The 33 m home radius is padded to 100 m for the iOS region, per the location rules.

## People and trackers

| Person | State | `source` | Linked trackers (person order) |
|---|---|---|---|
| `person.stephen_fenton` | home | `device_tracker.iphone_18_pro` | `iphone_18_pro`, `simulator_965a`, `iphone_fenton` |
| `person.stephanie_hobart` | not_home | `device_tracker.stephanies_iphone` | `stephanies_iphone` |

| Tracker | Integration | State | Linked to | Notes |
|---|---|---|---|---|
| `device_tracker.iphone_18_pro` | mobile_app | home | Stephen | Official app, iPhone19,2; live (battery, GPS accuracy about 5 m). Current person source |
| `device_tracker.iphone_fenton` | mobile_app | unknown | Stephen | This app's registration ("Stephen's iPhone · Fenton", iPhone19,2). No location sent yet |
| `device_tracker.simulator_965a` | mobile_app | unknown | Stephen | A simulator registration, linked to a real person |
| `device_tracker.stephanies_iphone` | mobile_app | not_home | Stephanie | Official app, iPhone13,3, live (GPS accuracy about 68 m) |
| `device_tracker.iphone_17_pro` | mobile_app | home | nobody | Stephen's previous phone ("Stephen's iPhone", iPhone18,1); stale since the last HA restart |
| `device_tracker.ipad` | mobile_app | home | nobody | iPad16,5; stale since the last restart |
| `device_tracker.simulator_5742`, `iphone_duo_simulator`, `galaxy_z_fold_8_emulator` | mobile_app | unknown | nobody | Debug and emulator registrations |
| `device_tracker.fordpass_…_tracker` | fordpass | home | nobody | The Mach-E; used by the garage journey automation |

Both people use `gps` trackers only; there are no router or Bluetooth trackers. Home Assistant's person entity follows the most recently updated GPS tracker among those linked to it, ignoring `unknown` and `unavailable`.

## household_presence

| Item | Value |
|---|---|
| Entity | `group.household_presence` (defined in `configuration.yaml`) |
| Members | `person.stephen_fenton`, `person.stephanie_hobart` |
| Rule | `all: false`: home if either person is home |
| State now | home |

Automations treat `home` to `not_home` (after a delay) as "everyone left" and `not_home` to `home` as "first person back".

## Thermostat Home/Away

| Item | Value |
|---|---|
| `sensor.thermostat_effective_home_away` | State `Home`, no attributes. A UI template helper (config entry, platform `template`), not in YAML |
| `sensor.thermostat_home_away_reason` | A second template helper; now "A resident is home, so TCS is using home behavior." |
| Consumer | The `thermostat_contact_sensors` custom component (TCS). It has an `away_presence_entity` option and a `vacation_mode_entity`; away is presence away or Vacation Mode on |
| Effect of away | Heat target 3 degrees lower, cool target 3 degrees higher by default (`away_heat_temp_diff`, `away_cool_temp_diff`); predictive comfort is skipped while away unless allowed |
| Now | `binary_sensor.thermostat_contact_sensors_away_mode_active` off; `binary_sensor.effective_vacation_mode` off |

Not verified: the template of the helper and the entity TCS is configured with. Both live in `.storage` config entry options, which the Home Assistant config rules forbid reading, and opening an options flow is a write call. Its name, reason text and "resident is home" wording point to person or household state plus vacation mode. Read the template in Settings, Devices and services, Helpers before relying on the exact inputs.

## Automations and scripts that use presence

Found in 260 automation and script configs (186 automations, 84 scripts) read through the API, plus a grep of `packages/`, `scripts.yaml` and `configuration.yaml`. Ten configs are YAML-only (404 from the config API); their YAML was grepped separately.

| Entity | Alias | Presence use |
|---|---|---|
| `automation.presence_all_home_members_away` | Presence - All Home Members Away | Trigger: household_presence home to not_home for 30 s. Action: arm Aqara away, lock the front door, close covers, switch off towel racks, resume lighting. Skips with a notification when a guest-stay toggle is on |
| `automation.presence_any_home_members_home` | Presence - Any Home Members Home | Trigger: household_presence not_home to home for 5 s. Action: arm Aqara home, towel racks on, clear the guest-stay reminder |
| `automation.aqara_arm_notification` | Aqara - Arm Notification | Condition: suppress the notice when armed_away while household_presence is not_home |
| `automation.front_door_recognized_arrival_presence_failsafe` | Front Door Recognized Arrival Presence Failsafe | Condition: group not_home with a recognized person at the opened door; waits 90 s for the group to go home |
| `automation.front_door_unsecured_lifecycle` | Front Door Unsecured Lifecycle | Trigger and actions: group state and timing; checks `person.stephen_fenton` `user_id` on notification acknowledgements |
| `script.front_door_contact_ownership` | Front Door Contact Ownership | Reads group state, members and `last_changed` to decide who owns a door notice |
| `automation.contact_notifications_v2_stephen` | Contact Notifications V2 Residents | Actions: front-door policy from group state and last change |
| `automation.master_suite_bedtime_preparation_lifecycle` | Master Suite Bedtime Preparation Lifecycle | Trigger: group home to not_home for 30 s ends bedtime preparation |
| `automation.master_bedroom_pbl_daytime_recovery` | Master Bedroom PBL - Daytime Recovery | Trigger: group home to not_home for 5 min; group state in conditions |
| `automation.master_bedroom_pbl_daytime_recovery_shadow` | Master Bedroom PBL - Daytime Recovery Shadow | Group state in a condition; records only |
| `automation.notify_on_past_due_chores` | Notify on past due chores | Triggers: each person to home; condition: that person home at 22:00 |
| `automation.location_based_grocery_notifications` | Location-Based Grocery Notifications | Zone triggers: each person entering the three passive store zones; clears on leaving |
| `automation.track_office_when_a_pc_is_on_and_someone_is_home` | Track Office When A PC Is On And Someone Is Home | Triggers: either person to or from home; HVAC office tracking only while someone is home |
| `automation.vacuum_cleaning_complete_notifications` | Vacuum Cleaning Complete Notifications | Action template checks `person.stephen_fenton` (and Stephanie) not_home |
| `automation.garage_door_status_2` | Garage Door Status | Chooses the person by door or vehicle and uses that person's `last_changed` |
| `automation.garage_journey_coordinator_shadow` | Garage Journey Coordinator - Stephen | Triggers: both persons' home-boundary transitions and the Mach-E tracker |
| `automation.household_journey_evidence_recorder` | Household Journey Evidence Recorder | Trigger and action: **`device_tracker.iphone_18_pro`** to home, hard-coded |
| `automation.solo_trip_reconcile` (package `solo_trip.yaml`) | Solo Trip reconcile | Triggers on either person's state while a solo trip is active; calls `script.household_away_command` |
| `script.household_away_command` (same package) | Household Away command | Reads the traveler person's state |
| `automation.sleepypod_bed_stage_schedules_to_mqtt` | SleepyPod bed stage schedules to MQTT | Calls `script.household_away_command` |
| Valetudo coordinator (package `valetudo_vacuum_coordinator.yaml`) | Main Floor Vacuum Coordinator | `people:` both persons; starts cleaning after both are away 300 s |

Custom components also read presence: `fenton_push` maps persons to their `mobile_app` registrations for notify targets, and `area_occupancy` can take a person entity per area (which areas use one is in UI config, not read).

## mobile_app registrations

| Device name | Model | OS | Tracker | Person link |
|---|---|---|---|---|
| iPhone 18 Pro | iPhone19,2 | 27.0 | `iphone_18_pro` | Stephen |
| Stephen's iPhone · Fenton | iPhone19,2 | 27.0 | `iphone_fenton` | Stephen |
| Stephen's iPhone | iPhone18,1 | 27.2 | `iphone_17_pro` | none |
| Stephanie's iPhone | iPhone13,3 | 26.3.1 | `stephanies_iphone` | Stephanie |
| iPad | iPad16,5 | 27.0 | `ipad` | none |
| Simulator 965A | arm64 | 27.0 | `simulator_965a` | Stephen |
| Simulator 5742, iPhone Duo Simulator | arm64 | 27.0, 27.1 | `simulator_5742`, `iphone_duo_simulator` | none |
| Galaxy Z Fold 8 Emulator | sdk_gphone64_x86_64 | Android 37 | `galaxy_z_fold_8_emulator` | none |

Nine registrations. Debug builds register with a `debug_` identifier prefix. The registry does not show which Home Assistant user owns each one; the person to user mapping is in `person` (`user_id`).

## What this means for the native app's tracker

- **It sits beside the official tracker.** `device_tracker.iphone_fenton` is already linked to `person.stephen_fenton`, behind `iphone_18_pro`. While it is `unknown` it is ignored; the first location it sends makes it a candidate for the person's source.
- **Linking changes the person source.** Once it reports, the person follows whichever of the two trackers updated last, so a stale, noisy or differently-timed native fix can flip Stephen between home and not_home. Shadow mode should keep reports from reaching the person until the app has matched the official tracker on real trips.
- **Away is expensive.** If both people read not_home, `group.household_presence` goes not_home and Home Assistant arms the alarm away, locks the front door, closes covers, switches off towel racks, and starts vacuum runs; TCS may also move the thermostat 3 degrees. Steph is not_home now, so Stephen going not_home (from a bad native fix) would trigger all of it.
- **Simulators are linked to Stephen.** `simulator_965a` is on his person. A simulator that reports a location (for example a simulated drive) can move him. Unlink simulator trackers, or keep the simulator on the no-report path, before the reporter is turned on.
- **Hard-coded tracker.** `household_journey_evidence_recorder` triggers on `device_tracker.iphone_18_pro` directly, so it will not see the native tracker even after it is linked. Journey automations work from person state otherwise.
- **iPad and old phone stay unlinked.** The iPad (`ipad`) must not be linked to a person (see the `isPresenceDevice` rule in [location.md](location.md)); `iphone_17_pro` is Stephen's previous phone and is stale.
