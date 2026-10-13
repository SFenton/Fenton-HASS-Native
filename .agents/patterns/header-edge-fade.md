# Header edge fade

> **What:** how scrolling content meets a page or modal header. **Read when:** touching a navigation bar background, a scroll-edge effect, a mask or a pinned header.

Owner, 2026-10-13: "Headers should not have the translucent background behind them in pages or modals. Content should fade as it scrolls up to the headers. Check FestivalNativeApps for a good implementation." Ported from FestivalNativeApps `ModalTopEdgeFade` (`apple/Sources/FestivalUI/Design/ModalTopEdgeFade.swift`, its `scroll-edge` pattern R2–R7).

## Rules

- **R1. One mechanism.** `HassDesign/HeaderEdgeFade.swift` `headerEdgeFade()` is the only place that hides the navigation bar background (`toolbarBackground(.hidden, for: .navigationBar)`) or the iOS 26 top scroll-edge effect (`scrollEdgeEffectHidden`), and the only top-edge content mask. Pages get it from `pageChrome()`; modals from `HassModal` or `modalChrome()`. Feature folders never add their own.
- **R2. Clear at the header, opaque 40 pt below it.** Content is fully transparent at the header's bottom edge and fully drawn `HeaderEdgeFade.rampHeight` (40 pt, the web `useScrollMask` `DEFAULT_SIZE`) below it. Nothing scrolls visibly behind the title or toolbar items.
- **R3. At rest, nothing is dimmed.** The ramp grows with the first 40 pt of scrolling (`progress(scrollOffset:)`), read from `onScrollGeometryChange` (iOS 18+).
- **R4. Hard edge for accessibility.** Reduce Transparency or Increase Contrast make the ramp 0: content is cut cleanly at the header, never dimmed and never shown under it. iOS 17 has no scroll reading and also gets the hard edge.
- **R5. Apply it inside the stack, on the page.** The modifier measures the page's top safe-area inset (the bar, a large title included, and anything pinned with `safeAreaInset(edge: .top)` outside it, such as `modalTabBar`). Every page pushed inside a modal applies `modalChrome()` itself; every page pushed on a section stack applies `pageChrome()`.
- **R6. Backgrounds are never masked.** The page backdrop is the navigation container's background (`pageBackdrop()`), outside the masked content.

HIG Scroll views: "Only use an edge effect when a scroll view is behind floating interface elements. It isn't decorative." With nothing scrolling behind the header, the effect is hidden.

## Tests

`Tests/HassDesignTests/HeaderEdgeFadeTests.swift` (geometry, ramp, R4); device screenshots in the chrome thread.
