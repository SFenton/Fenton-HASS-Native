# Room overview sheet

> **What:** the room-by-room sheets behind Home's Lights, Climate, Occupancy, Contact Sensors and Air Quality chips, and the room detail they push. **Read when:** changing any of those sheets, the Security page's Contact Sensors sheet, or a room page's lights, climate, occupancy or contact sheet.

Web source: `ha-sfenton-react-dash@f5a7bf9:src/pages/AtAGlancePage.tsx:247-1077` (`LightsSheet`, `ClimateSheet`, `OccupancySheet`, `ContactSheet`, `AirQualitySheet`), reused by `SecurityDashboard.tsx:180` and `DashboardViewPage.tsx:830-847`.

| Piece | Native |
|---|---|
| Titles, sections, subtitles, colors | `HassCore/Rooms/RoomOverview.swift` (pure, unit tested) |
| Group data | `HassCore/Rooms/RoomGroups.swift` (`LIGHT_GROUPS`, `CLIMATE_GROUPS`, `OCCUPANCY_GROUPS`, `CONTACT_GROUPS`, one list for Home and room pages) |
| Sheet + overview grid | `HassUI/Common/RoomOverview/RoomOverviewSheet.swift` |
| Room detail (page and content) | `HassUI/Common/RoomOverview/RoomGroupDetail.swift` |
| Light tile | `HassUI/Common/RoomOverview/LightGroupTile.swift` |

## Behavior

- **One sheet, five kinds** (`RoomOverviewKind`). Each opens full height (`.large`) with Done; a room tap pushes its detail page inside the sheet's own `NavigationStack` with Back (HIG: Sheets).
- **Overview sections.** Lights split into "Lights On" / "Lights Off" and Occupancy into "Occupied" / "Clear" (active first, an empty section dropped). Climate, Contact Sensors and Air Quality list every room under "Rooms". Headings sit inside the grid (`gridHeader()`), so every card in the sheet shares one height.
- **Room cards.** Title is the room; subtitle per web: lights "On" / "3 On" / group state ("Off"), climate the range helper truncated to one decimal (else the sensors' min–max, else "N sensors"), occupancy "Occupied" / "Not Occupied", contacts "Door Open" / "All Windows Closed" / "2 Doors Open". Active cards wash with the room's `AREA_ITEMS` color (lights: `LIGHT_ON_COLOR`; climate: the room's color helper) at 45% under the face's 60% wash; inactive cards are muted (no wash), like the web's `data-muted`. Air Quality cards are read-only and wash with each room's AQI color helper.
- **Sheet titles.** "Lights (3 On)" / "Lights (All Off)", then "Climate", "Occupancy", "Contact Sensors", "Air Quality". Detail pages take the web group title ("Living Room Lights", "Gym Light", "Office Climate", "Hallway Occupancy", "Entryway Contact Sensors") with the live subtitle as the page's first line (occupancy: "2 sensors occupied").
- **Room detail.** Lights: "Lights" heading, the room's group light as one full-width brightness tile when the room has several lights on a `light.` group, then each light (`LightGroupTile`: brightness tile when dimmable, else power tile; nightstands personalize to "Your Nightstand"). Climate: "Temperature Sensor(s)" and "Vent(s)" runs, tiles colored by vent state, the sensor's color helper, the temperature gradient, else the room color. Occupancy and contacts: "Occupancy Sensor(s)" / "Contact Sensor(s)" heading on Home, none on room pages (the sheet title names the group). Sensor tiles are read-only (`.state`).
- **Light commands** are explicit `turn_on` / `turn_off` and brightness through `LightControl`, never `toggle` (the web sheet sends `homeassistant.toggle`; Presence Based Lighting's Presence Lock reverts toggles). This is a recorded departure from web parity.
- **Equal tile heights.** Every grid uses `DynamicGridLayout(equalRowHeights: true)` inside `.equalHeightTiles()`: the tallest tile (Master Bedroom Closet wrapping to two lines on an iPhone) sets every row's height, measured on each layout pass so it follows Dynamic Type and rotation.
- **Chip summaries** (`HomeConfig.summary`): Lights counts each room light once ("All Off" / "3 On"), Contact Sensors each contact sensor ("All Closed" / "2 Open"), Occupancy reads "Detected" / "Clear", Air Quality "AQI x · PM2.5 y" from the house range helpers.
- **Privacy.** With `FENTON_REDACT_PRIVATE` set, occupancy subtitles read "Hidden" and drop their wash.
- **Identifiers.** `overview.<kind>`, `overview.<kind>.section.<title>`, `overview.<kind>.room.<room>`, `overview.detail.<room>`, `overview.detail.subtitle`, `room.lightGroup.<entity>`, `room.light.<entity>`, `room.entity.<entity>`.

## Consumers

Home (`HomeScreen` chip sheets), Security (`SecurityPage` Contact Sensors chip), room pages (`RoomSheetBody` lights, climate, occupancy, contacts, and the all-rooms contact sheet for Back Deck and Garage).
