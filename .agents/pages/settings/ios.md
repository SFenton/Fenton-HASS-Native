# Settings: Home Assistant settings modal (iPhone and iPad)

> **What:** the Settings tab's Home Assistant row and the full-screen modal it opens. **Read when:** changing `HassUI/Features/Settings`.

## Web source

- `ha-sfenton-react-dash@9ac2a46:src/constants/portedDashboard.ts` `SETTINGS_PAGE_ITEMS`: the last item, "Home Assistant Settings" (`mdi:cog`), links externally to `/config`. Copy from `src/i18n/locales/en/pages/settings.json` `items.homeAssistant`.
- Row shape: `DashboardViewPage.tsx` `SettingsLink` (icon, bold title, wrapping subtitle, accessory).
- The web dashboard runs inside Home Assistant, so it has no server, account or sign-out UI. The app owns its sign-in, so those live natively in the modal (departure from web parity, recorded here).

## Native

- `SettingsScreen` lists the Home Assistant row only until the household topics (Admin, Special Device Modes, Guests, Vacation, To-Do, Mach-E) are ported; that port adds the leading-pane split from [split-view](../../design/apple/split-view.md).
- The row opens `HomeAssistantSettingsView` with `fullScreenCover` (split-view.md: full-screen modal), so it is single-page on every device and pose. HIG: Modality (full-screen for an immersive, self-contained task with its own navigation), Settings.
- Sections: **Server** (address, connection, Home Assistant version), **Account** (`auth/current_user` name and role via `HassConnection.currentUser()`), **Home Assistant** (Settings `/config` for administrators and owners, Profile `/profile` for everyone), **Sign Out** with a confirmation dialog (HIG: Action sheets; destructive and needs a password to undo).
- Web pages push inside the modal's `NavigationStack` (Back returns to the form). `FrontendSession` writes the app's tokens into `localStorage.hassTokens` at document start, only on the server origin, in a non-persistent `WKWebsiteDataStore`, so the frontend opens signed in and nothing reaches disk. Off-server links open in the browser.
- `FENTON_REDACT_PRIVATE=1` hides the server address and user name for committed screenshots.

## Tests

- Unit: `FrontendSessionTests`, `TokenManagerTests.validTokensIncludeTheRefreshToken`, `SettingsViewTests` (copy, formatting, role gating, hosted render).
- Journeys (`SettingsJourneyTests`): Settings tab and modal audits (with AX5 relaunch), live connection and account rows, Settings web page opens signed in, Sign Out cancel then confirm, screenshot capture.
