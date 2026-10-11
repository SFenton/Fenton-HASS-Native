# Rooms: iPhone and iPad

> **What:** native room page notes. **Read when:** changing `HassUI/Features/Rooms` or `HassCore/Rooms`.

- Routing: `HomeRoute` (`Features/Home/HomeRoute.swift`) is the one registry for pages pushed under Home: rooms plus Media, Custom Lights, Sprinklers, Vacuums, Food and Grocery List. Lanes replace their placeholder in `HomeRouteDestination`; never add a second mechanism. Push with `.homeRouteDestination($route)` (`navigationDestination(item:)`), which works in plain and path-driven stacks.
- `RoomController` (HassCore) owns reads, sheet routing and service calls, so they are unit-tested without views; it shares one `MediaRemoteController` per remote with the page's remote sheet and app tiles.
- Quick Links is a toolbar button (HIG: Toolbars) on Home and every room, not the web's floating button. The sheet holds its own `NavigationStack` (Rooms and Security System push with Back); page links push after the sheet dismisses so the push never races the dismissal.
- Single page in every pose; the section grid goes to two columns when the window is wide (`DynamicGridLayout(minCellWidth: 340, maxColumns: 2)`). A Rooms list beside the room in landscape waits for the shell's on-demand split.
- Hook points for other lanes: `RoomCardView` (device tiles such as the bathroom fan and garage doors), the `.device` case in `RoomSheetBody` (air quality, humidifier, grill, dishwasher, bathroom fan, wake light, beds, vacuum), `QuickLinksSecurityDetail` (Security lane).
- Accessibility: identifiers `room.card.<title>`, `room.chip.<title>`, `room.sheet.<sheet>`, `room.section.<title>`, `quickLinks.<id>`, `rooms.<path>`. Read-only tiles are `.state` tiles (not buttons); tile faces inside links are one element so VoiceOver activates the link. Occupancy reads "Hidden" under `FENTON_REDACT_PRIVATE`.
- Gallery: `FENTON_GALLERY=rooms` (fixture store, recording caller, last call shown), `FENTON_GALLERY_ROOM=<path>` opens a room, `FENTON_GALLERY_QUICK_LINKS=1` opens Quick Links.
