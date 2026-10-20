# Authentication

> **What:** how the app signs in and keeps tokens. **Read when:** touching sign-in, tokens or the Keychain.

## Flow (`HassLoginFlow`)

Uses Home Assistant's login flow API, the same path the HA web login uses, so the user types username and password into a native form:

1. `POST /auth/login_flow` `{client_id, handler: ["homeassistant", null], redirect_uri}` → `flow_id`, `step_id: "init"`.
2. `POST /auth/login_flow/{flow_id}` `{client_id, username, password}` → either `type: "create_entry"` with `result` (the authorization code), or `type: "form"` with `step_id: "mfa"`, or `errors.base` (`invalid_auth`). **The app does not do the second step** (owner, 2026-10-17: never used): `HassLoginFlow.submitMFACode` stays in HassCore, but the screen has no code field, and an `mfa` step shows "Two-step sign-in isn't supported. Turn it off for this account in Home Assistant."
3. `POST /auth/token` (form-encoded) `grant_type=authorization_code&code=…&client_id=…` → `access_token`, `refresh_token`, `expires_in`.
4. Refresh: `grant_type=refresh_token&refresh_token=…&client_id=…`.
5. Sign out: `POST /auth/token` `action=revoke&token=<refresh_token>`, then clear the Keychain.

`client_id` is `HassServer.clientID` and `redirect_uri` shares its host, which Home Assistant accepts without fetching the client page. TODO(orchestrator): verify against the live server and confirm how the refresh token shows in the HA profile page.

## Sign-in screen (owner design, 2026-10-17)

`LoginView` / `LoginModel` (HassUI `Features/Login`). The server is fixed, `HassServer.fentonHome`: no address field (a debug build can point a journey elsewhere with `FENTON_HASS_SERVER`). Motion: [direction G, Launch and sign-in motion](../../design/direction-g.md).

- **Layout (always dark).** The radial ground `#3A4E73` → `#1E2A44` → `#121722` (`SignInGround`; `#121722` is also `LaunchBackground`, so the first frame matches the launch screen). A bare 96 pt house-and-heart (`SignInMark`, `HouseHeartShape`: no tile, the heart's ring is transparent so the ground shows) in the house colour of the saved `AppIconChoice` (`ActivityAppIconStore`, default Navy + Sky). "S+H" in 34 pt bold (VoiceOver: "S and H"), "Sign in to your Home Assistant", then a glass module (`#1C1C1E` at 66%, 26 pt radius, hairline) with Username and Password rows (label column and field, 52 pt, `.username` / `.password` content types so a password manager offers its entry, `submitLabel(.next)` then `.go`, Return moves to Password and then submits), a 50 pt capsule Sign In (`#0071E3`, white), and the footnote "Your password goes only to your Home Assistant. S+H keeps a sign-in key in your Keychain, never the password." At accessibility sizes the labels sit above the fields, the form scrolls, and the button stays reachable. iPad and the unfolded Duo: a centred column of at most 460 pt, any orientation.
- **Errors, in plain words, inline** (`LoginModel.Failure`):

  | Failure | Shown |
  |---|---|
  | Wrong username or password | Red (`#FF6961`) line with a warning glyph under the module: "That username and password don't match. Check them and try again."; the password row gets a red hairline, the password clears and takes focus, the username stays; VoiceOver announces it |
  | Server unreachable (offline, HTTP error from a gateway, a system error) | A red-tinted card above the module: "Can't reach Home right now" / "Check that this phone is online. If it is, Home Assistant may be restarting; try again in a minute." with a **Details** disclosure holding the raw reason (`HTTP 502`, the system error); the button reads **Try Again**; the fields keep their values |
  | Anything else | The same card: "Sign-in didn't work" with Details |
  | Two-step account | The red line: "Two-step sign-in isn't supported. Turn it off for this account in Home Assistant." |
- **Working.** Pressing Sign In scales the capsule to 0.96; the label becomes "Signing In…" with a white `ArcSpinner` inside the button (VoiceOver value "Signing In"); the fields dim to 50% and are off.
- **Session expired.** A rejected token (`HassConnection.Status.rejected`) used to sign out silently into a blank form. `AppSession.sessionExpired()` now keeps who it was (`RememberedAccount`: the last username, saved in `UserDefaults` on a successful sign-in, and the person's name the profile button already keeps under `shell.profileName`; never the password) and the screen shows **Welcome back, <first name>** with the person's monogram, the username read-only, only the password field, Sign In, and a **Use a Different Account** text button that forgets the account (`AppSession.forgetExpiredAccount()`). A phone that never remembered a username (signed in before this shipped) shows the plain form. A deliberate sign-out keeps the username to fill the next form, not the welcome back.
- **Debug switches (Debug builds).** `FENTON_SIGNIN_STUB=wrong|slow|success|unreachable|failed|twostep` answers the login flow from a canned `URLProtocol` (`DebugSignInStub`) so a journey sees every error without a failed sign-in on the real server (repeated refusals can get an address banned); `FENTON_EXPIRED_ACCOUNT=<username>|<name>` starts as if that session had ended; `FENTON_SKIP_INTRO=1` skips the intro (every journey but the intro's own); `FENTON_AUTOSIGNIN=1` (with `FENTON_HASS_USERNAME` / `_PASSWORD`) presses Sign In by itself after `FENTON_AUTOSIGNIN_DELAY` seconds, which is how the launch cost run signs in with no test driving the app.

## Storage

- Refresh token and server URL: Keychain, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, service `com.sfenton.home.auth`, in the app group `group.com.sfenton.home` so the notification service extension can fetch camera snapshots ([push](push.md)). An item saved before the group existed moves in on first read; a build without the entitlement keeps an unshared item.
- Sign-out clears the phone's push registration (`update_registration` with empty `app_data`) before revoking the refresh token.
- Access token: memory only, in `TokenManager` (an actor that refreshes 60 s before expiry and coalesces concurrent refreshes).
- The last username and the person's name (`RememberedAccountStore`, `UserDefaults`): not secrets, kept for the session-expired sign-in. `FENTON_UITEST_RESET` clears them.
- Never store the password. Never commit `temp.env` or any token.

## Web frontend hand-off

The Home Assistant settings modal opens `/config` and `/profile` signed in: `FrontendSession` stores the current tokens as `localStorage.hassTokens` (same shape and `clientId` the frontend uses) at document start, only on the server origin, in a non-persistent web data store. See [settings](../../pages/settings/ios.md).
