# Home

> **What:** platform-neutral spec for the Home (At a Glance overview) page. **Read when:** changing Home on any platform.

Source: `ha-sfenton-react-dash@9ac2a46:src/pages/AtAGlancePage.tsx` (render at lines 1244–1280), entity config in `src/constants/atAGlance.ts`.

## Layout, top to bottom

1. Title "Home".
2. Status rail (`OVERVIEW_STATUS_CHIPS`, atAGlance.ts:128):

| Chip | Entity | Summary | Opens |
|---|---|---|---|
| Lights | `light.lights` | "N on" across room light groups | Lights sheet: room light groups |
| Security | `alarm_control_panel.aqara_hub_m3_0056_security_system_2` | alarm state | Security system sheet |
| Climate | `input_text.all_climate_range` | the text value (temperature range) | Climate sheet |
| Occupancy | `binary_sensor.occupancy_sensors` | occupied / clear | Occupancy sheet |
| Contact Sensors | `binary_sensor.contact_sensors` | "N open" | Contact sensors sheet |

3. Weather summary (`weather.pirate_weather`): condition, temperature, today's high/low.
4. Guest presence and security section, shown only when a guest toggle is on (`input_boolean.guests_staying_in_guest_room`, `…_music_room`, `…_theater_room`).
5. Cameras (`CAMERA_ITEMS`, atAGlance.ts:281): Front Door (4:3), Driveway (10:3), Upper Deck (16:9), Lower Deck (16:9). Tap opens the camera viewer.

## States

| State | Behavior |
|---|---|
| Snapshot only (cold launch, offline) | Render saved values; quiet "Updating…" indicator |
| Live | Values update in place |
| Entity missing or `unavailable` | Chip shows "Unavailable", dimmed, still opens its sheet |

## Services

| Event | Service |
|---|---|
| Toggle a room light group (Lights sheet) | `light.toggle` on the group's `toggleEntityId` |
| Toggle a guest room | `input_boolean.toggle` |
