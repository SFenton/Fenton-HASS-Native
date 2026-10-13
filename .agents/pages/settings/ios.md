# Settings: Home Assistant settings modal (iPhone and iPad)

> **What:** the Settings tab's Home Assistant row and the full-screen modal it opens. **Read when:** changing `HassUI/Features/Settings`.

## Web source

- `ha-sfenton-react-dash@9ac2a46:src/constants/portedDashboard.ts` `SETTINGS_PAGE_ITEMS`: the last item, "Home Assistant Settings" (`mdi:cog`), links externally to `/config`. Copy from `src/i18n/locales/en/pages/settings.json` `items.homeAssistant`.
- Row shape: `DashboardViewPage.tsx` `SettingsLink` (icon, bold title, wrapping subtitle, accessory).
- The web dashboard runs inside Home Assistant, so it has no server, account or sign-out UI. The app owns its sign-in, so those live natively in the modal (departure from web parity, recorded here).

## Native

- `SettingsScreen` lists Vacation first ([vacation/ios.md](../vacation/ios.md)), then the admin To-Do ([chores/ios.md](../chores/ios.md), hidden from Steph, also a pushing `NavigationLink`), then the household topics ([household.md](household.md)) above the Home Assistant row. The leading-pane split comes with the navigation shell ([split-view](../../design/apple/split-view.md)). Vacation is a `NavigationLink` that pushes on the leading stack, not a split topic: moving it into `HouseholdSettingsPage` so it opens in the trailing pane is a follow-up.
- The row opens `HomeAssistantSettingsView` with `fullScreenCover` (split-view.md: full-screen modal), so it is single-page on every device and pose. HIG: Modality (full-screen for an immersive, self-contained task with its own navigation), Settings.
- Sections: **Server** (address, connection, Home Assistant version), **Account** (`auth/current_user` name and role via `HassConnection.currentUser()`), **Home Assistant** (Settings `/config` for administrators and owners, Profile `/profile` for everyone), **Sign Out** with a confirmation dialog (HIG: Action sheets; destructive and needs a password to undo).
- Web pages push inside the modal's `NavigationStack` (Back returns to the form). `FrontendSession` writes the app's tokens into `localStorage.hassTokens` at document start, only on the server origin, in a non-persistent `WKWebsiteDataStore`, so the frontend opens signed in and nothing reaches disk. Off-server links open in the browser.
- `FENTON_REDACT_PRIVATE=1` hides the server address and user name for shared screenshots.

## Tests

- Unit: `FrontendSessionTests`, `HassConnectionUserTests` (over `HAMockConnection`), `TokenManagerTests.validTokensIncludeTheRefreshToken`, `SettingsViewTests` (copy, formatting, role gating, account loading, web-session hand-off, hosted renders). `ImageRenderer` runs a view's `.task`, so a hosted render of the connected modal sends its own `currentUser` request; render it after completing the requests a test checks.
- Journeys (`SettingsJourneyTests`): Settings tab and modal audits (with AX5 relaunch), live connection and account rows, Settings web page opens signed in (no web login form), Sign Out cancel then confirm (audits the confirmation), screenshot capture.
- iOS 27 shows the sign-out confirmation as a popover anchored to the row, with no Cancel button (an outside tap cancels) and a nested duplicate of the confirm button; the audit can dismiss it.
- Folded iPhone Duo: tabs are a rail (Settings is the `gearshape` button), bar buttons move to the rail (Back is `BackButton`), the form is taller than the screen and the bar hides while it is scrolled, so journeys scroll rows and Done into view.
- Web-page screenshots stay out of the repo: Home Assistant's Settings dashboard lists repairs, pending updates and installed integrations.
