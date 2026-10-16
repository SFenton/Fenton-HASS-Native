# Performance tests

> **What:** how scroll smoothness is measured and where the numbers go. **Read when:** a page stutters, or after changing a page's layout, tiles, images or live-update path.

- **Fast-scroll tests:** `Apps/iOSUITests/FastScrollPerformanceTests.swift`. Each page from the debug gallery's fixtures is flicked down and up at full speed, five measured iterations after a warm-up pass. Metrics:
  - `scrollDecelerationMetric` and `scrollDraggingMetric` (the system hitch ratio);
  - the app's `EntityUpdate` and `ImageDecode` signposts;
  - clock and CPU.
  - `testFlickLiveTabs` flicks Home, Security and Climate on the live server (`TEST_RUNNER_FENTON_PERF_LIVE=1` plus credentials).
- **Physical device only.** Simulators report false hitch data, so the measured tests skip there. The smoke test `testEveryPageFlicksWithoutLosingContent` runs everywhere and is part of the normal journeys.
- **Running:** `tools/ios_perf.sh --device "<iPhone name>"`. Add `--live --env <temp.env>` for live pages, or `--only testFlickRecipes` for one page. Open the `.xcresult` in Xcode to read metrics and set baselines per device.
- **In the app:** Settings → Performance shows the same pages' hitch ratios from real use, plus MetricKit's daily scroll hitch ratio. Export Telemetry shares the JSON. See [telemetry](../../patterns/telemetry.md).
- **Targets (Apple):** hitch ratio under 5 ms/s is good, 5–10 is noticeable, over 10 is bad.
- **Adding a page:**
  1. Give its scroll view an identifier and `.scrollTelemetry("<Page>")`.
  2. Add a `Page` entry and a `testFlick<Page>` method.
- **Chip rail:** `testSwipeChipRail` swipes Home's six-chip rail along a 120-tile page (`FENTON_GALLERY_PERF=chips`), device only like the others; `testChipRailSwipesWithoutLosingContent` runs everywhere. Set the baseline per device in Xcode.
- **Finding a nested-scroll cost on the simulator** (chip rail, 2026-10-16). Hitch metrics are false there, and `XCTCPUMetric` is dominated by XCUITest's accessibility snapshots (every variant measured the same), so profile instead: build Release with `SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) DEBUG'` (keeps the gallery), start the swipe test, `xcrun xctrace record --template "Time Profiler" --device <UDID> --attach <app PID> --time-limit 25s` (attach by PID: `--attach FentonHome` matches the UI test runner), `xctrace export --xpath '/trace-toc/run/data/table[@schema="time-profile"]'`, and count main-thread samples under `ScrollViewCommitMutation.apply`, `ViewGraphRootValueUpdater._updateViewGraph` and `CA::Transaction::commit`. Vary one thing at a time (tile count, chips, the header fade); a cost that grows with the *page* rather than the scrolled content means the scroll is writing into the page's view graph. Logging body evaluations (`NSLog` in `body`) shows whether a swipe re-renders anything.
