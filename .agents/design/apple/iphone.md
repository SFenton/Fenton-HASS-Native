# iPhone

> **What:** iPhone navigation and presentation decisions. **Read when:** building any iPhone screen.

- **Portrait only** (owner, 2026-10-10): Info.plist `UISupportedInterfaceOrientations~iphone` is portrait; never add landscape layouts for iPhone.
- Tab bar with the web's primary nav (`routes.ts` `PRIMARY_NAV_ROUTES`). SF Symbols replace MDI icons. On iOS 26 and later (`CompactTabLayout`): Home, Security, Climate and Chores, then Quick Links as the separate trailing tab (`Tab(role: .search)`, like FestivalNativeApps' Search); a phone shows five tabs before "More" and the trailing tab counts, so Settings opens from the leading menu button (`NavigationFlyout`) on each section root. Before iOS 26 all five sections are tabs and Quick Links is a toolbar button. Owner, 2026-10-13. HIG Tab bars: "Avoid overflow" and "A dedicated Search tab may be trailing."
- Profile: `ProfileButton` (initials, or a person symbol) is the trailing-most item on every section root and opens Home Assistant settings and the account. The web's header Profile opens the Daily Report, not yet ported.
- Large navigation titles on tab roots; sub-pages push with the system Back button. A page shows Back or the tab bar root, never a second menu (web UX contract, page headers).
- Web hash modals (`#lights-overview`, `#security-system`, cameras) become SwiftUI sheets with `.presentationDetents([.medium, .large])`; camera viewers use `.large` only.
- Respect safe areas with system layout; never hard-code notch or Dynamic Island insets (web safe-area contract).
