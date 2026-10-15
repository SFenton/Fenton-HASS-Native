# Native push notifications

> **What:** how Home Assistant notifications reach the app natively, and how a notification's buttons, links and attachments behave. **Read when:** touching notifications, the notification service extension, `mobile_app` registration, or sign-out.

Owner decision (2026-10-14): native notifications through our own push path, replacing the companion app for alerts. The server half is the Fenton Push integration, [`SFenton/ha-fenton-push`](https://github.com/SFenton/ha-fenton-push), whose `docs/CONTRACT.md` (v1) both halves follow. Automations keep calling `notify.*` with the companion app's `data` keys; the integration's relay turns them into APNs pushes for this app.

## Path

```
automation ─ notify.mobile_app_<device>_fenton ─▶ mobile_app ─ POST push_url ─▶ Fenton Push relay ─ APNs ─▶ phone
                                                                                                     │
       Home Assistant ◀─ webhook: update_registration, fire_event ◀─ app ◀─ tap / button ◀───────────┘
```

| Piece | Where |
|---|---|
| Config, payload, links, categories, attachments | `HassCore/Push` (logic, 95% bar) |
| Registration and its webhook (shared with location) | `HassCore/MobileApp`, `HassUI/App/MobileApp` ([mobile-app](mobile-app.md)) |
| Session wiring, taps, buttons, `clear_notification` | `HassUI/App/Push/PushCoordinator.swift`; `ShellNavigator.open(_:)` |
| System glue (permission, APNs token, `UNUserNotificationCenterDelegate`) | `Apps/iOS/FentonHomeApp.swift`, `Apps/iOS/SystemPushPlatform.swift` |
| Notification Service Extension (`com.sfenton.home.NotificationService`) | `Apps/NotificationService/` |

## Registration (contract rules 1-2)

- After sign-in, once the websocket is up and the user is known (`MainTabView.loadProfileName`): ask for alert, sound and badge permission (once per install), `registerForRemoteNotifications`, then sync.
- Sync: `GET /api/fenton_push/config`. The registration is shared with location and sensors ([mobile-app](mobile-app.md)): **404 (integration not installed) registers websocket-only** (since 2026-10-15; push used to register nothing). `available: false`, a foreign `bundle_id` or no APNs token: register without push details; a later `update_registration` adds them. `push_websocket_channel` stays off until the app subscribes to `mobile_app/push_notification_channel` (claiming it without listening makes Home Assistant think a token-less phone is reachable).
- One webhook per Home Assistant user per server, in the Keychain (`KeychainMobileAppRegistrationStore`, service `com.sfenton.home.push`). Reused on the next sign-in as that user; `update_registration` on every launch and token change; a 410 from the webhook forgets it and registers again.
- `device_name` is `"<UIDevice name> · Fenton"`, so the notify service never collides with the official app's on the same phone.
- `apns_environment` comes from `embedded.mobileprovision` (`aps-environment`): sandbox for Xcode installs and the simulator, production for TestFlight and the App Store.
- Sign-out sends `update_registration` with `app_data: {}` **before** the refresh token is revoked (`AppSession.signOut`).
- Debug UI journeys keep push off (no prompt, no registration) when launched with `FENTON_HASS_TOKEN`, `FENTON_UITEST_RESET` or `FENTON_GALLERY`, unless `FENTON_PUSH=1` (`PushLaunchPolicy`).

## Payload (contract rule 3)

- `userInfo.fenton` (`PushPayload`): `v`, `tag`, `group`, `url`, `actions[]`, `entity_id`, `image`, `video`, `attachment.url`, `command`, `ext` (an automation's own `data.fenton`), `extra` (unmapped keys such as `presentation_options`). A newer `v` is ignored.
- Taps open `url`; a button with `uri` opens that; other buttons fire `mobile_app_notification_action` through the webhook with `action`, `tag` and, for text input, `reply_text`. Home Assistant decides what happens: the app never acts on a button itself.
- Links are read like the web dashboard reads them (`routes.ts` `routePathFromUrl`): `/sfenton-react-dash/home?path=<route>#<anchor>`. Sections open at their root (`overview`, `security`, `thermostat`, `chores` and its sub-routes, `settings` and its sub-routes); Home pages push on Home (rooms, Groceries, Vacuums, Media; Food detail pages open the Food hub). Anchors are not scrolled to yet. Other Home Assistant paths and other sites open in the browser.
- Background push `{"aps":{"content-available":1},"fenton":{"command":"clear_notification","tag":…}}` removes delivered notifications with that tag. Other commands are ignored for now.

## Service extension

- Replaces the relay's `fenton.dynamic` category with one built from the buttons (`PushCategory`: a stable hash of the buttons; at most 32 built categories are kept, others are untouched). Buttons: `sfsymbols:<name>` icons, `authenticationRequired`, `destructive`, `activationMode: foreground`, `behavior: textInput`.
- Threads by `group` when the relay sent no `thread-id`.
- Attaches, in order: the camera snapshot for a `camera.*` `entity_id` (`/api/camera_proxy/<entity_id>`), then `image`, `video`, `attachment.url`. Server paths and same-server URLs carry the signed-in user's token, read from the Keychain item the app shares through the app group `group.com.sfenton.home` (`KeychainTokenStore.sharedAccessGroup`; an older unshared item moves in on first read). Size limits: 10 MB image, 50 MB video, 5 MB file.
- Anything that fails leaves the notification as sent.

## Live camera (content extension, `com.sfenton.home.NotificationContent`)

- A notification with a `camera.*` `entity_id` gets the fixed category `fenton.camera` (`PushCategory.camera`, set by the service extension), which the content extension serves; it sets the notification's buttons at runtime (`extensionContext.notificationActions`) and forwards presses to the app (`.dismissAndForwardAction`).
- It shows the attached snapshot, then streams Home Assistant's MJPEG (`/api/camera_proxy_stream/<entity_id>`, token header, `MJPEGFrameScanner`), and switches to HLS (`camera/stream` over a commands-only websocket, `HassConnection.connect(subscribingToStates: false)`) when that plays. Debug builds print the step in the view.
- **Link `UserNotificationsUI.framework` explicitly and keep `ENABLE_DEBUG_DYLIB: NO`.** Without it the extension crashed on the phone in `EXConcreteExtensionContextVendor _extensionContextClass` before any app code (seen 2026-10-14).
- Status 2026-10-15 (paused by the owner): the expanded view shows the snapshot, but the live video never started, and the extension wrote no trace lines at all, so start by checking whether `didReceive(_:)` runs and whether the extension can write to the app group. The app's websocket also drops on Stephen's server ("Received frame with non-zero reserved bits"), which would break HLS.

## Debugging on a phone

- Debug builds write `Library/Caches/push-trace.log` in the app group (`PushTrace`: step names, entity ids, HTTP statuses; never tokens or text). Copy it with `xcrun devicectl device copy from --device <udid> --domain-type appGroupDataContainer --domain-identifier group.com.sfenton.home --source Library/Caches/push-trace.log --destination <file>` (devicectl reads only `Library`, `Documents` and `tmp`).
- Extension crashes: `xcrun devicectl device info files --device <udid> --domain-type systemCrashLogs`, then `copy from` the `.ips`.
- Verified on Stephen's iPhone 18 Pro (2026-10-15, Debug, sandbox): registration and `update_registration` (rename to "Stephen's iPhone · Fenton"), real APNs delivery, buttons from the payload, and the camera snapshot attachment. `notify.fenton_stephen` (person targets) works with Fenton Push 0.1.1, which calls each device's own `notify.mobile_app_<device>_fenton` (verified 2026-10-15).

## Routing on Stephen's server

- 2026-10-15 (owner's request): the YAML notify group "Stephen's Phone" (`notify.stephen_s_phone`, `/config/configuration.yaml`) lists `fenton_stephen` after `mobile_app_iphone_18_pro`, so every automation that notifies Stephen, and `notify.household` (which nests it), reaches both the official app and Fenton. Backup `configuration.yaml.bak-20261015-080415-fenton`. Stephanie's group is unchanged until she runs Fenton.

## Testing

- Logic: `HassCoreTests/PushTests.swift`, `HassUITests/PushCoordinatorTests.swift` (REST double: `HassTestSupport/StubHTTPTransport`).
- Device journeys: `PushJourneyTests` with `tools/push_sim.sh <udid> <folder>` running beside `tools/ios_uitest.sh` (same folder in `TEST_RUNNER_FENTON_CAPTURE_DIR`; `send-<fixture>.ready` asks for a push, other `.ready` files for a host screenshot); fixtures in `tools/push_fixtures/`. Simulator push is the bar until the APNs key exists; device delivery is deferred.
- `xcrun simctl push` never runs service extensions, and the simulator refuses content-available-only pushes ("no user visible content"; seen 2026-10-14, iOS 27). Debug builds therefore have two hooks that run the same code paths: `FENTON_PUSH_PREVIEW` (a base64 `.apns` shown as a local notification after `PushEnrichment` and `PushAttachmentLoader`, after `FENTON_PUSH_PREVIEW_DELAY` seconds) and `FENTON_PUSH_COMMAND` (a base64 background payload run through `handleBackground` at launch). The extension itself is verified only with real APNs.
- After each boot the iOS 27.0 simulator can take minutes to answer `requestAuthorization` (the alert, or a stored answer, arrives late; seen 2026-10-14), and it refuses timed local requests ("Source is not authorized"), so the preview waits in the app and posts at once. Journeys allow 240 s for a preview banner; keep the simulator warm between runs.
- An attached camera snapshot did not show a thumbnail on the iOS 27.0 simulator preview even when no error was logged (2026-10-14); confirm attachments on a device with real APNs.
- In the extension, camera snapshots need a password sign-in (the token launch keeps its token in memory, out of its reach); the preview hook uses the launch token directly.

## Open

- Real APNs: needs Stephen's APNs key in the integration; TestFlight builds need `aps-environment: production` at archive.
- Critical alerts need Apple's Critical Alerts entitlement for `com.sfenton.home`; until then the integration sends time-sensitive.
- Notification settings UI goes under the Account sheet after Direction G Phase 2 (#68) lands.
