# Authentication

> **What:** how the app signs in and keeps tokens. **Read when:** touching sign-in, tokens or the Keychain.

## Flow (`HassLoginFlow`)

Uses Home Assistant's login flow API, the same path the HA web login uses, so the user types username and password into a native form:

1. `POST /auth/login_flow` `{client_id, handler: ["homeassistant", null], redirect_uri}` → `flow_id`, `step_id: "init"`.
2. `POST /auth/login_flow/{flow_id}` `{client_id, username, password}` → either `type: "create_entry"` with `result` (the authorization code), or `type: "form"` with `step_id: "mfa"` (ask for the one-time code, then post `{client_id, code}` to the same URL), or `errors.base` (`invalid_auth`, `invalid_code`).
3. `POST /auth/token` (form-encoded) `grant_type=authorization_code&code=…&client_id=…` → `access_token`, `refresh_token`, `expires_in`.
4. Refresh: `grant_type=refresh_token&refresh_token=…&client_id=…`.
5. Sign out: `POST /auth/token` `action=revoke&token=<refresh_token>`, then clear the Keychain.

`client_id` is `HassServer.clientID` and `redirect_uri` shares its host, which Home Assistant accepts without fetching the client page. TODO(orchestrator): verify against the live server and confirm how the refresh token shows in the HA profile page.

## Storage

- Refresh token and server URL: Keychain, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, service `com.sfenton.home.auth`, in the app group `group.com.sfenton.home` so the notification service extension can fetch camera snapshots ([push](push.md)). An item saved before the group existed moves in on first read; a build without the entitlement keeps an unshared item.
- Sign-out clears the phone's push registration (`update_registration` with empty `app_data`) before revoking the refresh token.
- Access token: memory only, in `TokenManager` (an actor that refreshes 60 s before expiry and coalesces concurrent refreshes).
- Never store the password. Never commit `temp.env` or any token.

## Web frontend hand-off

The Home Assistant settings modal opens `/config` and `/profile` signed in: `FrontendSession` stores the current tokens as `localStorage.hassTokens` (same shape and `clientId` the frontend uses) at document start, only on the server origin, in a non-persistent web data store. See [settings](../../pages/settings/ios.md).
