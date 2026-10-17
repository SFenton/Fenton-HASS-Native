# iPhone

> **What:** iPhone navigation and presentation decisions. **Read when:** building any iPhone screen.

- **Portrait only** (owner, 2026-10-10): Info.plist `UISupportedInterfaceOrientations~iphone` is portrait; never add landscape layouts for iPhone.
- Tab bar with the web's primary nav (`routes.ts` `PRIMARY_NAV_ROUTES`): Home, Security, Climate, Chores and Settings, five tabs, Settings last (owner, 2026-10-16). SF Symbols replace MDI icons. One `TabView` on every system (the glass floating bar on iOS 26). Quick Links is a header button, not a tab (the trailing `Tab(role: .search)` and `CompactTabLayout` are gone).
- Header: every page, root or pushed, carries two trailing 44 pt glass circles, Quick Links (`quickLinks.open`) then Profile (`ProfileButton`, initials or a person symbol, badged with overdue chores plus expired food, `nav.profile`). Profile opens the Account sheet, the web's Your Summary ([settings/ios.md](../../pages/settings/ios.md)).
- The title shares the header row with the circles: `toolbarTitleDisplayMode(.inlineLarge)` from `pageChrome()` draws the large title leading in the bar and collapses it to a centred inline title on scroll (HIG Toolbars, iOS: a large title "by default becomes standard while scrolling and returns to large at the top"). A pushed page with a Back button keeps the system large title below the bar. Sub-pages push with the system Back button. A page shows Back or the tab bar root, never a second menu (web UX contract, page headers).
- Web hash modals (`#lights-overview`, `#security-system`, cameras) become SwiftUI sheets with `.presentationDetents([.medium, .large])`; camera viewers use `.large` only.
- Respect safe areas with system layout; never hard-code notch or Dynamic Island insets (web safe-area contract).
