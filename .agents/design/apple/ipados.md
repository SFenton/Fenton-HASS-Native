# iPadOS

> **What:** iPad navigation decisions. **Read when:** building for regular width.

- Navigation: the overlay flyout from FestivalNativeApps (slides over content with a scrim, never resizes content), not a persistent sidebar. Until it lands, the scaffold uses the iPhone `TabView`. TODO(orchestrator): port `FestivalDrawer`.
- Rotates freely. Portrait is always single page; landscape may split.
- Splits follow [split-view.md](split-view.md): on demand, landscape regular width only, 50/50 at the midpoint.
- Grids grow columns with width through `DynamicGridLayout`; no fixed four-column ceilings (web UX contract).
