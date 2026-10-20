# Location and device sensors

> **What:** how the app reports location and device sensors to Home Assistant through `mobile_app`. **Read when:** touching `HassCore/MobileApp`, `HassCore/Location` or the location permission screen.

Plan and rationale: the owner's "Location, Home/Away and device sensors" report (2026-10-14), and the 2026-10-20 report that made reporting unconditional and added the person link.

## Shape

| Piece | Where | Role |
|---|---|---|
| `MobileAppWebhookClient` | `HassCore/MobileApp` | `update_location`, `register_sensor`, `update_sensor_states`, `get_zones` to `/api/webhook/<id>`; 410 → `.registrationGone` |
| `MobileAppWebhookSource` | same | Supplies the current webhook: the shared registration store ([mobile-app](mobile-app.md)) |
| `LocationReport`, `HAZone`, `ZonePlanner`, `ZoneEventResolver`, `LocationFixFilter`, `LocationTrigger` | same | Pure reporting rules (below) |
| `MobileAppSensor`, `MobileAppSensorProvider`s, `DeviceStatus` | same | Sensors from one device reading |
| `LocationReporter` | `HassCore/Location` | Drives permission, zones, significant changes and fixes over the `LocationPlatform` seam |
| `CoreLocationPlatform` | same, iOS only | `CLLocationManager` + iOS 17 `CLMonitor` |
| `LocationPermissionView` | `HassUI/Features/Location` | The explainer and permission steps ([page](../../pages/settings/location.md)) |
| `LocationCoordinator`, `LocationLaunchPolicy`, `LocationPermissionPresenter` | `HassUI/App/Location` | Starts and stops the reporter with the registration and permission; offers the screen once after sign-in |
| `PresenceLinker`, `PresenceLinkOutcome`, `HassCommandSending` | `HassCore/MobileApp` | Adds this phone's tracker to the signed-in user's person (below) |

One `mobile_app` registration per phone, shared with push ([mobile-app](mobile-app.md)), so each phone is one Home Assistant device. Webhook calls carry no token (the id addresses the registration) and never use the websocket: they are one-off exchanges, not entity state.

## Rules

- **Permission:** While Using the App first, then the upgrade to Always, with Precise Location. Background reporting (zones, significant changes) needs Always and Precise; While Using sends a fix on app open only.
- **Zones:** at most 20 regions (iOS limit). `zone.home` always; passive zones never; the rest nearest to the last fix by distance to their edge; radii under 100 m padded to 100 m. Conditions are added `assuming: .unsatisfied`, so the first evaluation reports only the zone the phone is in, never a burst of exits.
- **Zone result:** enter sends `location_name` `home` (home zone) or the zone's name; exit sends `not_home` only when the fix is outside every non-passive zone by more than its accuracy, otherwise no name (Home Assistant computes it). An enter with no fix sends the zone's center at its radius' accuracy; an exit with no fix sends nothing.
- **Filter:** drop invalid fixes; drop accuracy over 200 m unless a zone event caused the fix; drop a fix within 10 m and 30 s of the last one sent unless the trigger is Manual. A fix that fails to send never becomes the duplicate reference.
- **Body:** whole numbers; leave out anything Core Location marks invalid (negative speed, course, accuracies). Altitude below sea level is valid; it is left out only when vertical accuracy is negative.
- **Failures:** 410 or no webhook stops reporting until the phone registers again; other errors keep it running and show in `lastError`.
- **iPad:** never a presence device by default (`LocationReporter.isPresenceDevice(isPad:)`): an iPad left at home and tied to a person would mark them home.

## Matching the official app

Names, unique ids, state strings and icons mirror `home-assistant/iOS` (`Sources/Shared/API/Webhook/Sensors`, `WebhookSensorId`, `LocationUpdateTrigger`) so templates only change the device prefix. Entity ids come from the device name plus the sensor name, so the names matter most.

| Sensor | unique_id | Notes |
|---|---|---|
| Battery Level / Battery State | `battery_level` / `battery_state` | `Charging`, `Full`, `Not Charging` |
| Connection Type, SSID, BSSID | `connectivity_connection_type`, `connectivity_ssid`, `connectivity_bssid` | SSID/BSSID need the Access Wi-Fi Information entitlement; `Not Connected` off Wi-Fi |
| Location permission | `location-permission` | `Authorized Always`, `Authorized when in use`, … plus a `Precise` attribute (ours) |
| Last Update Trigger | `last_update_trigger` | `Launch`, `Geographic Region Entered`, `Geographic Region Exited`, `Significant Location Change`, `Background Fetch`, `Push Notification`, `Manual` |
| Geocoded Location | `geocoded_location` | Mailing address; parts as attributes, `N/A` when unknown |
| App Version, Storage, Audio Output | `app-version`, `storage`, `iphone-audio-output` | Storage: opportunistic ÷ total, 2 decimals, `% available` |
| Focus | `focus` | Binary sensor |

The brief's shorthand ids (`ssid`, `region entered`) were replaced by the official ones above (2026-10-14).

## Reporting and the person link (2026-10-20)

Owner report: got home with the official app uninstalled and this app was not marked home despite Share Location Always and Report to Home Assistant on. Root causes, fixed here:

1. **Reporting was gated behind a hidden switch.** `LocationCoordinator.startIfReady` returned unless `isReportingArmed` (`location.reportingArmed`, default false) was set. The switch is gone: whenever a webhook exists and the permission is While Using or Always, the reporter runs.
2. **Nothing linked the tracker to a person.** Home Assistant follows only the `device_trackers` listed on a person; the app registered `device_tracker.<name>` but never touched the person. `PresenceLinker` now does (below).
3. **Background reporting was already wired** (`UIBackgroundModes: location`, significant changes, `CLMonitor` zones from `get_zones`, `update_location` on each event; usage strings in `project.yml`) but was dead while disarmed. It needs Always and Precise Location; While Using reports one fix per foreground only.

- **Phones only.** The app delegate creates `LocationCoordinator` at launch when `LocationLaunchPolicy.isEnabled` (not on iPad; not in test-token, reset or gallery launches unless `FENTON_LOCATION=1`). An iPad never shows the permission screen or links a person.
- **Offer once.** After sign-in, once the notification alert is answered (`MainTabView.loadProfileName`), the permission screen is offered once per install while there is something to ask.
- **Start and stop.** The reporter starts when a webhook exists (this session's sync, or one saved by an earlier launch, so a background relaunch for a zone event reports without the websocket) and the permission is While Using or Always. Each return to the foreground sends a `Launch` fix. Sign-out stops it. A 410 syncs once, which registers again.
- **No toggle.** Reporting follows the permission; the Profile tab shows Share Location only.

### Presence link (`PresenceLinker`, `HassCore/MobileApp`)

On every sign-in (`MainTabView.loadProfileName`, after the registration sync) and again after the first accepted location update (Home Assistant creates the tracker lazily), `MobileAppCoordinator.linkPresence` runs `PresenceLinker.link` over the websocket:

1. `config/entity_registry/list`: find the `mobile_app` `device_tracker` whose `unique_id` is this registration's webhook id; if it is disabled, enable it (`config/entity_registry/update`).
2. `person/list`: find the person whose `user_id` is the signed-in user.
3. If the tracker isn't in that person's `device_trackers`, `person/update` with the existing list plus the tracker (append only; nothing else sent). Already listed: no call.

The registration itself already belongs to the signed-in user (the registrations API registers as the token's user). Outcomes (`PresenceLinkOutcome`) show in Share Location's section as an `InlineAlert`: `needsAdmin` (these commands are admin-only; owners and admins are tried, others skip without sending), `noPerson` (no UI-managed person has this user; YAML persons can't be edited), `trackerMissing`, `failed`. A linked or already-linked result is silent and isn't repeated for the same registration and user in a session; unlinked outcomes retry at the next connection or first report.

### Turning location off, on, and signing out (2026-10-20)

- **Off** (denied, restricted, no longer authorized): the reporter stops and the phone's tracker is taken off the person. Why: Home Assistant keeps a tracker's last state, so a phone that can no longer report would hold "home" for good and block the person's other trackers from being believed. Removing it (only this tracker) lets the others decide. Best effort.
- **On again**: the reporter starts at once (fresh `Launch` update, zones re-planned) and the tracker is linked again.
- **Sign-out** waits for `PresenceLinker.unlink` (`AppSession.confirmedSignOut`). Already unlinked, no person, or no tracker counts as success so retries never stick; any failure shows "Sign Out couldn't complete. Try again." and stays signed in. The `mobile_app` registration stays (webhook saved, push cleared as before), so the next sign-in as that user reuses the device. Non-admin users never linked anything and sign out directly. Journeys stub the failure with `FENTON_SIGNOUT_FAIL=1`.
- Skipped: Mac steps (macOS is no longer a target; the macOS-only `AppSessionTests` are untouched).

## Inventory

What Home Assistant does with presence today (zones, people, trackers, the automations that react): [presence-inventory](presence-inventory.md).
