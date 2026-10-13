# Content gate

> **What:** how a page waits for its content before showing it. **Read when:** a page or sheet loads data asynchronously (a service response, a REST fetch, images), not when it reads `EntityStore`.

- **Component:** `ContentGate(page:isReady:content:)` (`HassDesign/Loading/ContentGate.swift`). Web source: the recipe results region phases (`ha-sfenton-react-dash@f5a7bf9:src/components/hass/recipes/useRecipeCollection.ts:47-49`, `src/pages/RecipesPage.module.css`).
- **Sequence:**
  1. While loading, the content is laid out but hidden (opacity 0, no hit testing, hidden from VoiceOver).
  2. A centered spinner labeled "Loading" fades in after 150 ms, so a fast load never flashes it.
  3. Once `isReady` is true **and** every reported piece of content is ready, the spinner fades out (140 ms). The content then fades in and rises 4 pt (170 ms; Reduce Motion keeps the fade and drops the rise).
  4. When `isReady` goes back to false (a new search, a reload), the content fades out (170 ms) and the sequence repeats.
- **Readiness of children:**
  - `CachedImage` (and so `RemoteImage` and `ImageCard`) reports itself, so a gated grid waits for its visible images.
  - Anything else can report with `.contentReadiness(id, isReady:)`.
  - The gate stops waiting after `ContentGateModel.Timing.childTimeout` (1.5 s), so one slow image never holds the page.
- **No reload on reopen:** a gate created with `isReady == true` shows content immediately, with no spinner and no fade. Pass the cached or snapshot state as ready. Never gate a page that reads `EntityStore`: the store is always ready from the disk snapshot.
- **Telemetry:** each cold load is a `ContentReady` interval named by `page`. Instant shows are counted (`gate.instant`).
- **Tests:**
  - `Tests/HassDesignTests/ContentGateTests.swift` (the phase machine with an injected sleeper).
  - `PerformanceJourneyTests.testGateShowsSpinnerThenContent` (gallery `FENTON_GALLERY=performance`, `FENTON_GALLERY_PERF=gate`).
- HIG: Loading; Progress indicators (indeterminate for unknown waits); Motion (Reduce Motion).
