# Shared mobile_app registration

> **What:** the one `mobile_app` registration each phone keeps per Home Assistant user, which push, location and sensors share. **Read when:** touching registration, sign-out, the webhook, or adding a feature that sends through `mobile_app`.

One phone is one Home Assistant device. Push ([push](push.md)), location and sensors ([location](location.md)) all go through the same registration, so the phone gets one `notify.mobile_app_<device>_fenton`, one `device_tracker` and one set of sensors.

## Shape

| Piece | Where | Role |
|---|---|---|
| `MobileAppRegistrar` | `HassCore/MobileApp` | Register, `update_registration`, sign-out (`app_data: {}`), notification button events |
| `MobileAppRegistration`, `MobileAppDevice` | same | The webhook per user and server; the device facts sent |
| `MobileAppRegistrationStore` (`KeychainMobileAppRegistrationStore`, `InMemoryMobileAppRegistrationStore`) | same | One webhook per user and server, plus the active one. Also the `MobileAppWebhookSource` location and sensors send through |
| `HomeAssistantPushClient` | `HassCore/Push` | `GET /api/fenton_push/config` and the registration endpoints |
| `MobileAppCoordinator` | `HassUI/App/MobileApp` | The session's registrar, user and APNs token; publishes `registration` and tells listeners when it changes |
| `PushCoordinator.mobileApp` | `HassUI/App/Push` | Push owns the coordinator (the app delegate's object), asks for notification permission, then syncs |

## Rules

- **When:** after sign-in, once the websocket is up and the user is known (`MainTabView.loadProfileName` → `PushCoordinator.didConnect`), on every new APNs token, and once more after a webhook answers 410.
- **Fenton Push optional (contract change, 2026-10-15):** `GET /api/fenton_push/config` answering **404, or `available: false`, registers websocket-only** (no `push_url`, `push_token` or `apns_environment`), so location and sensors work on a server without the integration. A later sync adds the push details once the integration answers. Other config errors (5xx, network) stop the sync, so a broken integration never clears working push details. This replaces push's earlier "404 registers nothing"; `SFenton/ha-fenton-push` `docs/CONTRACT.md` §1 needs the same change.
- **One per user:** the webhook is reused on the next sign-in as the same user; a 410 forgets it and registers again.
- **Keychain item:** service `com.sfenton.home.push` (push's original name, kept so phones that registered before the move keep their device), this-device-only, after first unlock.
- **Sign-out:** `update_registration` with empty `app_data` before the refresh token is revoked; the store's active webhook is cleared, which stops location at once.
- **Simulator never registers (2026-10-15).** Every simulator signs in as a real person, so each one (and each erase) used to add a `mobile_app` device and a `notify` service to that person. `MobileAppRegistrar` refuses `sync` in the simulator (`Refusal.simulator`, nothing sent) unless the launch sets `FENTON_MOBILE_APP_REGISTER=1` (`MobileAppRegistrationPolicy`), and `MobileAppCoordinator` ignores a webhook saved before the rule. Journeys that need a registration use stubs (`StubHTTPTransport`, `InMemoryMobileAppRegistrationStore`); push journeys don't need one (`simctl push` targets the bundle, and buttons and `clear_notification` run through the debug hooks).
- **Journeys:** a test-token, reset or gallery launch never registers (`PushLaunchPolicy`, unless `FENTON_PUSH=1`) and keeps webhooks in memory, so a journey sign-out never touches a real registration.

## Tests

`HassCoreTests/PushTests.swift` (registrar, stores, webhook source, the simulator rule), `HassUITests/LocationCoordinatorTests.swift` (`MobileAppCoordinatorTests`), `HassUITests/PushCoordinatorTests.swift`.
