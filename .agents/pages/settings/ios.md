# Settings: Home Assistant settings modal (iPhone and iPad)

> **What:** Settings (inside the Account sheet behind the profile avatar since direction G), its Home Assistant row and the full-screen modal that row opens. **Read when:** changing `HassUI/Features/Settings`.

## Web source

- `ha-sfenton-react-dash@9ac2a46:src/constants/portedDashboard.ts` `SETTINGS_PAGE_ITEMS`: the last item, "Home Assistant Settings" (`mdi:cog`), links externally to `/config`. Copy from `src/i18n/locales/en/pages/settings.json` `items.homeAssistant`.
- Row shape: `DashboardViewPage.tsx` `SettingsLink` (icon, bold title, wrapping subtitle, accessory).
- The web dashboard runs inside Home Assistant, so it has no server, account or sign-out UI. The app owns its sign-in, so those live natively in the modal (departure from web parity, recorded here).

## Native

- **Settings is the last tab (owner, 2026-10-16).** `SettingsTabRoot` (`Features/Settings/SettingsTabRoot.swift`) hosts `SettingsScreen` as the root of the Settings stack on the wallpaper (rows are `moduleThin` list rows). Every push is a value on the tab's path (`SettingsRoute`: Vacation, To-Do, Performance; `HouseholdSettingsPage`: the household topics), registered by `MainTabView.sectionStack`, so `ShellNavigator.isAtRoot(.settings)` is false on a topic and the flyout's edge swipe leaves the edge to the system back swipe. Home Assistant settings and the Feedback forms stay a full-screen cover and sheets. A topic is never split; Profile and Quick Links ride in the header of each pushed page. A notification for Settings opens the tab (`PushDestination.section(.settings)`).
- **Account sheet = the web's profile modal (owner, 2026-10-16).** The Profile button opens `AccountSheet` (a form sheet on iPad): who is signed in, then `ProfileSummarySections` (the web's Daily Report, "Your Summary": People at Home, the viewer's Overdue and Upcoming Chores as checkable rows, Expired Food from `sensor.evershelf_expired_items` on the local calendar; logic in `HassCore/Profile/ProfileSummary`), Location on phones and Sign Out behind an alert. There is no Settings row. The Profile button carries the web's badge (overdue chores plus expired food, "9+", spoken in its value).
- A **Feedback** section ends the list: Report an Issue and Request a Feature ([feedback.md](feedback.md)).
- `SettingsScreen` lists Vacation first ([vacation/ios.md](../vacation/ios.md)), then the admin To-Do ([chores/ios.md](../chores/ios.md), hidden from Steph), then the household topics ([household.md](household.md)) above the Home Assistant row, then Performance. Each of Vacation, To-Do, Performance and the topics is a value pushed on the Settings tab.
- The row opens `HomeAssistantSettingsView` with `fullScreenCover` (split-view.md: full-screen modal), so it is single-page on every device and pose. HIG: Modality (full-screen for an immersive, self-contained task with its own navigation), Settings.
- Sections: **Server** (address, connection, Home Assistant version), **Account** (`auth/current_user` name and role via `HassConnection.currentUser()`), **Home Assistant** (Settings `/config` for administrators and owners, Profile `/profile` for everyone), **Sign Out** with a confirmation dialog (HIG: Action sheets; destructive and needs a password to undo).
- Web pages push inside the modal's `NavigationStack` (Back returns to the form). `FrontendSession` writes the app's tokens into `localStorage.hassTokens` at document start, only on the server origin, in a non-persistent `WKWebsiteDataStore`, so the frontend opens signed in and nothing reaches disk. Off-server links open in the browser.
- `FENTON_REDACT_PRIVATE=1` hides the server address and user name for shared screenshots.

## Tests

- Unit: `FrontendSessionTests`, `HassConnectionUserTests` (over `HAMockConnection`), `TokenManagerTests.validTokensIncludeTheRefreshToken`, `SettingsViewTests` (copy, formatting, role gating, account loading, web-session hand-off, hosted renders). `ImageRenderer` runs a view's `.task`, so a hosted render of the connected modal sends its own `currentUser` request; render it after completing the requests a test checks.
- Journeys (`SettingsJourneyTests`, reaching Settings with `XCUIApplication.openAccountSettings()`): Settings and modal audits (with AX5 relaunch), live connection and account rows, Settings web page opens signed in (no web login form), Sign Out cancel then confirm (audits the confirmation), screenshot capture.
- iOS 27 shows the sign-out confirmation as a popover anchored to the row, with no Cancel button (an outside tap cancels) and a nested duplicate of the confirm button; the audit can dismiss it.
- Folded iPhone Duo: tabs are a rail, bar buttons move to the rail (Back is `BackButton`), the form is taller than the screen and the bar hides while it is scrolled, so journeys scroll rows and Done into view.
- Web-page screenshots stay out of the repo: Home Assistant's Settings dashboard lists repairs, pending updates and installed integrations.
