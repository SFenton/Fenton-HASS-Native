# Security: iPhone and iPad

> **What:** native Security implementation notes. **Read when:** changing `HassUI/Features/Security`.

- `SecurityScreen` passes the live `HassConnection` (as `HassServiceCalling`) to `SecurityPage`, which the debug gallery (`FENTON_GALLERY=security`) also hosts with fixture state and a recording caller. Journeys press controls only in the gallery; the signed-in journey opens the real tab read-only. HIG: Navigation bars, Scroll views.
- Status rail reuses `StatusRail` with the Security and Contact Sensors chips (`idPrefix: "security"`). Security opens `SecuritySystemSheet`; Contact Sensors opens the shared `ChipSheet(.contacts)`.
- Tiles are `GlassTile`s on `DynamicGridLayout` (min width scales with Dynamic Type, max 4 columns): the alarm tile navigates (chevron), the lock and garage tiles are commands with hints ("Unlocks", "Closes the door"). Values are the state text, so VoiceOver reads "Front Door, Locked". HIG: Buttons.
- Garage doors run `HassCore/Security/GarageDoorController` (timers on `RevertScheduler`, unit-tested with a manual clock). `SecurityScreen.canSend` maps disconnected / waiting / rejected to "cannot send", which fails an active request like the web's `connectionCannotSend`. Feedback is announced with `AccessibilityNotification.Announcement`.
- Shared with Rooms: garage room cards draw `GarageDoorTile` (`RoomCardView.garageTile` keeps the card title), and the Quick Links Security System detail reuses `SecurityControls`, the body of the Security System sheet.
- The mode sheet uses medium/large detents; Disarmed confirms with an alert (Cancel always present on every device, unlike an action-sheet popover). HIG: Alerts.
- `FENTON_REDACT_PRIVATE=1` hides the alarm mode (tile, sheet header and selection) in shared screenshots.
- Gallery flags: `FENTON_GALLERY_FAIL=1` fails every call (garage error state), `FENTON_GALLERY_CLEAN=1` hides the last-call line.
