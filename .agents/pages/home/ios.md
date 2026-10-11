# Home: iPhone and iPad

> **What:** native Home implementation notes. **Read when:** changing `HassUI/Features/Home`.

- `HomeScreen` is a `ScrollView` in a `NavigationStack` with a large title. HIG: Navigation bars, Scroll views.
- Status rail: `StatusRail` horizontal scroll, chips 44 pt min height. HIG: Buttons (hit targets).
- Sheets: `HomeSheet` enum → `.sheet(item:)`, detents per [modal-sheet](../../patterns/modal-sheet.md).
- Cameras: `CameraGrid` on `DynamicGridLayout`; tiles show the camera's `entity_picture` snapshot (tokenized URL, no auth header needed), refreshed when the entity updates. The viewer (`CameraViewer` → `Features/Cameras/CameraLiveView`) plays live video over that snapshot: WebRTC first through the WebRTC integration's `/api/webrtc/ws` (signed with `auth/sign_path`, go2rtc stream ids `front_door`, `garage_camera`, `upper_deck`, `lower_deck`; same protocol as `SFenton/WebRTC` `www/stream-manager.js`), then core HLS (`camera/stream`) if WebRTC shows no frame within 10 s, then the snapshot with a retry. The snapshot cross-fades out only on the first frame, streams stop in the background and resume on return, and `FENTON_REDACT_PRIVATE` keeps the blurred snapshot over the video. Video only for now (no audio). HIG: Playing video (live content shows its state; no scrubbing controls for a live feed).
- Pending sheets (Security system, Climate, Occupancy, Contacts) show their entity lists read-only for now.
