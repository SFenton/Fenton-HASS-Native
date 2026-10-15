# Location and device sensors

> **What:** how the app reports location and device sensors to Home Assistant through `mobile_app`. **Read when:** touching `HassCore/MobileApp`, `HassCore/Location` or the location permission screen.

Plan and rationale: the owner's "Location, Home/Away and device sensors" report (2026-10-14). Today the official Home Assistant app is the household's only presence source; this app runs in shadow until its tracker has matched the official one on real trips.

## Shape

| Piece | Where | Role |
|---|---|---|
| `MobileAppWebhookClient` | `HassCore/MobileApp` | `update_location`, `register_sensor`, `update_sensor_states`, `get_zones` to `/api/webhook/<id>`; 410 → `.registrationGone` |
| `MobileAppWebhookSource` | same | Supplies the current webhook. Implemented by the shared registrar once registration moves out of push (Phase 1); until then only tests and the gallery |
| `LocationReport`, `HAZone`, `ZonePlanner`, `ZoneEventResolver`, `LocationFixFilter`, `LocationTrigger` | same | Pure reporting rules (below) |
| `MobileAppSensor`, `MobileAppSensorProvider`s, `DeviceStatus` | same | Sensors from one device reading |
| `LocationReporter` | `HassCore/Location` | Drives permission, zones, significant changes and fixes over the `LocationPlatform` seam |
| `CoreLocationPlatform` | same, iOS only | `CLLocationManager` + iOS 17 `CLMonitor` |
| `LocationPermissionView` | `HassUI/Features/Location` | The explainer and permission steps ([page](../../pages/settings/location.md)) |

One `mobile_app` registration per phone, shared with push, so each phone is one Home Assistant device. Webhook calls carry no token (the id addresses the registration) and never use the websocket: they are one-off exchanges, not entity state.

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

## Not wired yet

`LocationReporter` is not started by the app; nothing reads the device yet (no `DeviceStatus` source for battery, network, storage, audio, Focus or geocoding). Phase 1 lifts registration out of push and implements `MobileAppWebhookSource`; Phase 2 starts the reporter after sign-in and adds the Account sheet row; Phase 3 adds the device readers and the Focus capability.
