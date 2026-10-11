# iPadOS

> **What:** iPad navigation decisions. **Read when:** building for regular width.

- Navigation: the overlay flyout from FestivalNativeApps (slides over content with a scrim, never resizes content), not a persistent sidebar. Built in `HassUI/App/Shell/` (`NavigationFlyout`, `ShellNavigator`, `ShellNavigationStyle`):
  - Regular width (iPad, unfolded Duo, any orientation) hides the root `TabView`'s bar and shows **Open Navigation** (`nav.open`, `line.3.horizontal`) on each section root; a leading-edge swipe opens it while the section is at its root. Compact width (iPhone, folded Duo) keeps the tab bar (web `bottom` layout). The style follows the size class only, so rotation never swaps the navigation model.
  - Rows follow the web rail/drawer (`AdaptiveNavigation.tsx`): heading "Navigation", Home, Security, Climate, Chores, then Settings pinned at the bottom (scrolls with the rows at large text sizes). Only Chores carries a badge (`ShellNavigator.overdueChores`, web `BADGED_NAV_PATH`), spoken as "Chores, N overdue".
  - Closes on a destination, scrim tap, Escape (`.cancelAction`) or the VoiceOver escape gesture. Opening focuses the heading; closing without a destination returns focus to Open Navigation. The content is hidden from VoiceOver while it is open.
  - Every page in a section stack applies `.pageChrome()` (pushed pages too) so the tab bar stays hidden in flyout style; section roots also apply `.sectionRootChrome()`.
  - Departure from the web: the web shows a persistent 248 px rail at ≥1120×820; the native app follows the owner's FestivalNativeApps verdict (persistent sidebars looked bad; overlay flyout instead).
- Rotates freely. Portrait is always single page; landscape may split.
- Splits follow [split-view.md](split-view.md): on demand, landscape regular width only, 50/50 at the midpoint.
- Grids grow columns with width through `DynamicGridLayout`; no fixed four-column ceilings (web UX contract).
