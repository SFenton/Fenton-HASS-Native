# Home

> **What:** platform-neutral spec for the Home (At a Glance overview) page. **Read when:** changing Home on any platform.

Source: `ha-sfenton-react-dash@9ac2a46:src/pages/AtAGlancePage.tsx` (render at lines 1244–1280), entity config in `src/constants/atAGlance.ts`.

## Layout, top to bottom

1. Title "Home".
2. Status rail (`OVERVIEW_STATUS_CHIPS`, atAGlance.ts:128):

| Chip | Entity | Summary | Opens |
|---|---|---|---|
| Lights | `light.lights` | "All Off" / "N On" across every room light | Lights overview: Lights On / Lights Off rooms → room lights |
| Security | `alarm_control_panel.aqara_hub_m3_0056_security_system_2` | alarm state | Security system sheet |
| Climate | `input_text.all_climate_range` | the text value (temperature range) | Climate overview: rooms → temperature sensors and vents |
| Occupancy | `binary_sensor.occupancy_sensors` | Detected / Clear | Occupancy overview: Occupied / Clear rooms → presence sensors |
| Contact Sensors | `binary_sensor.contact_sensors` | "All Closed" / "N Open" across every contact sensor | Contact overview: rooms → doors and windows |
| Air Quality | `input_text.all_aqi_range` (+ `input_text.all_pm25_range`, icon color `input_text.all_aqi_color`) | "AQI x · PM2.5 y" | Air Quality overview: rooms (read-only) |

Sheets: [room-overview-sheet](../../patterns/room-overview-sheet.md) (source `ha-sfenton-react-dash@f5a7bf9:src/pages/AtAGlancePage.tsx`).

3. Weather summary (`weather.pirate_weather`): condition, temperature, today's high/low.
4. Guest presence and security section, shown only when a guest toggle is on (`input_boolean.guests_staying_in_guest_room`, `…_music_room`, `…_theater_room`).
5. Cameras (`CAMERA_ITEMS`, atAGlance.ts:281): Front Door (4:3), Driveway (10:3), Upper Deck (16:9), Lower Deck (16:9). Tap opens the camera viewer.

## States

| State | Behavior |
|---|---|
| Snapshot only (cold launch, offline) | Render saved values at once, no spinner; the reconnecting arc in the header only after 2 s without a connection |
| First sign-in (no snapshot yet) | Tiles show names and a soft pulsing bar for the value until live data lands |
| Live | Values update in place |
| Entity missing or `unavailable` | Chip shows "Unavailable", dimmed, still opens its sheet |

## Services

| Event | Service |
|---|---|
| Turn a room's light or group on/off or set brightness (room detail) | `light.turn_on` / `light.turn_off` (`brightness_pct`); switches `switch.turn_on` / `turn_off`. Never `toggle` (departure: the web sends `homeassistant.toggle`, which Presence Based Lighting reverts) |
| Toggle a guest room | `input_boolean.toggle` |
