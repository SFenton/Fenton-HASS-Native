# Apple platform

> **What:** Swift architecture and runtime invariants. **Read when:** writing any Swift.

| File | Holds |
|---|---|
| [architecture.md](architecture.md) | Package layout and shared components |
| [auth.md](auth.md) | Sign-in flow, token storage and refresh |
| [connection-lifecycle.md](connection-lifecycle.md) | Websocket, backgrounding, snapshot cache, in-place updates |
| [build-and-run.md](build-and-run.md) | XcodeGen, SwiftPM tests, simulators |
| [capacity.md](capacity.md) | Machine-wide simulator, device and build slots (`tools/devcap.py`) |
| [location.md](location.md) | Location and device sensors through `mobile_app` |
| [live-activities.md](live-activities.md) | Live Activities spec: the Home activity, the Fenton Push job engine, push-to-start and update tokens; §0 holds Phase 1's verified facts and device checks |
| [live-activities-ha-automations.md](live-activities-ha-automations.md) | The Home Assistant automations Phase 1 proposes (not applied): start, update, end and the activity's buttons |
