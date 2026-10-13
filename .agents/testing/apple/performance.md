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
