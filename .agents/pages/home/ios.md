# Home: iPhone and iPad

> **What:** native Home implementation notes. **Read when:** changing `HassUI/Features/Home`.

- `HomeScreen` is a `ScrollView` in a `NavigationStack` with a large title. HIG: Navigation bars, Scroll views.
- Status rail: `StatusRail` horizontal scroll, chips 44 pt min height. HIG: Buttons (hit targets).
- Sheets: `HomeSheet` enum → `.sheet(item:)`, detents per [modal-sheet](../../patterns/modal-sheet.md).
- Cameras: `CameraGrid` on `DynamicGridLayout`; first pass shows the camera's `entity_picture` snapshot (tokenized URL, no auth header needed), refreshed when the entity updates. Camera plan (decided in the dashboard inventory): snapshot tiles first, then HLS, then WebRTC via go2rtc stream ids (`front_door`, `garage_camera`, `upper_deck`, `lower_deck`).
- Pending sheets (Security system, Climate, Occupancy, Contacts) show their entity lists read-only for now.
