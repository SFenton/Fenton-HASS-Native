# iPhone

> **What:** iPhone navigation and presentation decisions. **Read when:** building any iPhone screen.

- **Portrait only** (owner, 2026-10-10): Info.plist `UISupportedInterfaceOrientations~iphone` is portrait; never add landscape layouts for iPhone.
- Tab bar with the web's primary nav: Home, Security, Climate, Chores, Settings (`routes.ts` `PRIMARY_NAV_ROUTES`). SF Symbols replace MDI icons.
- Large navigation titles on tab roots; sub-pages push with the system Back button. A page shows Back or the tab bar root, never a second menu (web UX contract, page headers).
- Web hash modals (`#lights-overview`, `#security-system`, cameras) become SwiftUI sheets with `.presentationDetents([.medium, .large])`; camera viewers use `.large` only.
- Respect safe areas with system layout; never hard-code notch or Dynamic Island insets (web safe-area contract).
