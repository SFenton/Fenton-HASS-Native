# Performance tests

> **What:** how scroll smoothness is measured, what it showed, and the rules that came out of it. **Read when:** a page stutters, or after changing a page's layout, tiles, images or live-update path.

- **Two tools, two questions.**
  - *What does a surface cost the main thread?* The scroll cost probe, on a simulator (below). It reads CPU instructions and per-run-loop-turn main-thread time, which do not move with other work on the Mac.
  - *Does a frame make its deadline on the phone?* The fast-scroll tests on a physical device (further down). Simulators render with the Mac's compositor, so their hitch ratios and any GPU cost are false.

## Scroll cost (simulator)

The app measures itself (`HassUI/Diagnostics/ScrollCostProbe.swift`, `HassTelemetry/MainThreadCostMeter.swift`). With `FENTON_SCROLLCOST=1` and `FENTON_SCROLLCOST_AUTORUN=<seconds>` it waits for the page to settle, stands still for 8 s (the floor), then moves the front scroll view up and down at 900 pt/s for 8 s, twice, and reports:

| Key | Meaning |
|---|---|
| `minstr` | CPU instructions the process retired, in millions |
| `main_ms` | CPU time the main thread used |
| `over4` `over8` `over16` | run-loop turns whose main-thread CPU time passed 4, 8 and 16 ms; `over8` is a dropped frame at 120 Hz |
| `p95_ms` `worst_ms` | the 95th percentile and the longest turn |
| `deliveries` `changed` `update_ms` | live updates applied meanwhile, and the main-thread time applying them |
| `travelled` | points scrolled, to put runs of different length on one footing |

- **Run it:** `tools/ios_scrollcost.sh [--section gallery|live] [--only "Living Room"] [--env temp.env] [--compare BASE.tsv]`. It builds the app optimized (`-O`: the Release code path, gallery still in), runs every surface in `tools/scrollcost-surfaces.txt` on one simulator inside a devcap hold, and prints `tools/scrollcost_report.py`'s table. About a minute a surface.
- **Why not an XCUITest swipe.** The first attempt flicked pages with `swipeUp` under `XCTCPUMetric`. Every page read the same 2.6 to 2.9 G instructions, a Grid of 300 tiles included: what it measured was the accessibility snapshot the swipe asks of the app, not the page. The probe's own display link moves the scroll view, and nothing touches the app while it measures.
- **Gallery or live.** `[gallery]` surfaces run on fixtures with no connection, so the number is the page alone. `[live]` surfaces sign in with the token and open a page with `FENTON_SCROLLCOST_OPEN=<dashboard path>`: live entity updates and camera streams are in the number, which is how the owner's phone behaves. Compare like with like. Whole-process `minstr` is not comparable between live runs (the camera streams alone retire about 20 G instructions in 8 s on any page); compare `main_ms`, `over8`, `p95_ms` and `update_ms`.
- **Tests:** `Apps/iOSUITests/ScrollSurfacesPerformanceTests.swift` holds the surfaces that were slow to a budget (`TEST_RUNNER_FENTON_PERF_ON_SIMULATOR=1`, and the token for the `testLive*` ones). Budgets, from the post-fix numbers: p95 turn 6 ms on fixtures and 3.5 ms live, no turn over 8 ms, none over 16 ms in the warm run, 25 ms of live-update work and 100 ms of main-thread time for a standing-still live page in 8 s.
- **Unit tests:** `MainThreadCostMeterTests` (the report), `HomeColumnsTests` (the scroll-invariant container), `EntityDeliveryOffMainTests` (deliveries cross to the main actor in order, a burst is diffed once).

### Found (2026-10-16, iPhone 17 Pro simulator, iOS 27.0, optimized build, live house)

**Applying live updates took over half of the main thread's CPU time.** HAKit sends the whole set of entities (thousands) on every change; its cache rebuilt a `Set` of them on the main queue, and `HassConnection.receive` rebuilt a dictionary of them and compared each to the last, also on the main thread. A Time Profiler trace of a page standing still: 1646 of 4113 main-thread samples (40%) in `HassConnection.delta`, another 624 (15%) in HAKit's cache transform. Nine milliseconds a delivery, four to seven deliveries a second: every delivery was a dropped frame at 120 Hz, on every page, scrolling or not. Fixed: HAKit's callback queue is now `HassConnection.deltaQueue`, so the cache, the diff and a burst's coalescing run off the main thread, and only the changed entities hop to the main actor ([connection lifecycle](../../platforms/apple/connection-lifecycle.md)).

| Live page, scrolling 8 s | main-thread p95 turn | longest turn | turns over 8 ms | live-update time on main |
|---|---|---|---|---|
| Climate | 6.1 → 1.8 ms | 85 → 9.6 ms | 26 → 0 | 398 → 0.8 ms |
| Recipes | 2.9 → 1.5 ms | 71 → 9.3 ms | 26 → 0 | 406 → 1.0 ms |
| Media | 3.0 → 1.6 ms | 144 → 5.9 ms | 25 → 0 | 442 → 0.4 ms |
| Theater Room | 3.1 → 1.8 ms | 91 → 8.1 ms | 19 → 0 | 276 → 0.4 ms |
| Chores | 3.0 → 1.8 ms | 50 → 7.3 ms | 26 → 0 | 346 → 0.5 ms |
| Living Room | 3.2 → 1.9 ms | 32 → 7.7 ms | 22 → 0 | 269 → 0.5 ms |
| Master Bedroom | 2.9 → 2.0 ms | 30 → 11 ms | 20 → 0 | 261 → 0.9 ms |
| Food hub | 2.3 → 1.7 ms | 29 → 8.6 ms | 19 → 0 | 279 → 0.4 ms |
| Pantry | 2.8 → 1.9 ms | 37 → 8.5 ms | 20 → 0 | 261 → 0.4 ms |

A page standing still (fixtures plus live updates): main-thread CPU in 8 s 439 → 3 ms (Living Room), 616 → 6 (Grid), 1562 → 5 (Climate), 787 → 7 (Chores); the 95th-percentile turn 18 to 49 ms → 0.05 ms. The updates' work did not vanish, it moved: process CPU is about the same (0.85 s in 8 s), on another core.

**Home scrolled with a state write per frame.** `HomeScreen` measured the space its content is offered with `frame(in: .global)` inside the scroll view, so the frame changed on every frame of a scroll and each change wrote `@State`, re-evaluating the page. It now keeps the horizontal position and the size only (`HomeColumns.container(from:)`).

**What is left, and not ours to fix here.**
- Scrolling itself costs 0.5 to 0.65 s of main-thread CPU in 8 s on a static page (about 1.2 ms a frame, p95 1.5 to 2 ms live, 2 to 4 ms on fixtures), nearly all inside UIKit and SwiftUI: `UINavigationController` observing the content scroll view for the large title (`_observeScrollViewDidScroll`, 3% of the main thread's samples on the Grid and Recipes, 12% on a room page) and SwiftUI's attribute graph propagating the offset (`ScrollViewCommitMutation.apply` → `AG::Graph::propagate_dirty`). It grows with the number of views: about 1.6 M instructions per tile per 1000 pt (Grid of 300 tiles: 556 M per 1000 pt, p95 5.8 ms; Living Room about 40 tiles: 186 M, p95 3.7 ms; Climate: 138 M). `GlassTile`'s per-tile geometry observer was tried (removed for tiles without an accessory) and moved the Grid by 4%, so it is not the cause.
- **Camera streams keep running on every tab.** A page that shows no camera still costs 3.2 CPU-s in 8 s live against 0.85 in the gallery, because shown streams are retained for the session ([camera streams](../../patterns/camera-streams.md)). The cameras lane owns it; on a phone the decode is in hardware, so the evidence is battery and heat rather than frames.
- Sheets that fit one screen (most of them on a 874 pt phone: bed, wake light, purifier, remotes, Security System, Climate Advanced) have nothing to scroll; their cost is drawing when they open, which this probe does not read.
- Weather sheet: the rain and snow decoration is a 24 fps `TimelineView` that runs while the sheet is open (965 M instructions in 8 s standing still, in the gallery's rain scene).
- GPU cost: the simulator cannot show it. See below.

## What only a phone can settle

Run these on the iPhone 18 Pro (nothing here has been run on it):

```bash
# 1. The fix, on the real house, release build: scroll cost per live page.
tools/ios_scrollcost.sh --device 00008160-00022D8230914036 --label phone-base
# 2. GPU layers, one at a time. headerFade is the mask under the navigation bar (a full-page offscreen pass while scrolling);
#    backdrop is the blurred house photo. Compare the two runs: p95 and over8 should not move if the layer is free.
tools/ios_scrollcost.sh --device 00008160-00022D8230914036 --label phone-nofade --disable headerFade
tools/ios_scrollcost.sh --device 00008160-00022D8230914036 --label phone-nobackdrop --disable backdrop
python3 tools/scrollcost_report.py apple/.build/scrollcost-phone-nofade.tsv --compare apple/.build/scrollcost-phone-base.tsv
# 3. Hitches the system sees (FastScrollPerformanceTests, below), before and after.
tools/ios_perf.sh --device 00008160-00022D8230914036 --live --env temp.env --only testFlickLiveTabs
```

`FENTON_PERF_DISABLE` (`HassDesign/PerfSwitches.swift`) only turns a layer off for that launch; a normal launch has everything on.

## Rules

- **No work on the main thread proportional to the number of entities.** A change to one entity costs the main thread one box update ([connection lifecycle](../../platforms/apple/connection-lifecycle.md)).
- **No state written from a geometry read that moves with a scroll.** `onGeometryChange` / `GeometryReader` in or around scrolling content that reads `frame(in: .global)` (or any scrolling space) fires every frame; return a value that does not change with the scroll (the size, the horizontal position) or write nothing.
- **A closure given to HAKit runs off the main thread.** Mark it `@Sendable` or build it in a `nonisolated` function.
- **Measure CPU with instructions and run-loop turns, never with an XCUITest swipe or a simulator hitch ratio.**

## Fast-scroll tests (physical device)

- `Apps/iOSUITests/FastScrollPerformanceTests.swift`. Each page from the debug gallery's fixtures is flicked down and up at full speed, five measured iterations after a warm-up pass. Metrics:
  - `scrollDecelerationMetric` and `scrollDraggingMetric` (the system hitch ratio);
  - the app's `EntityUpdate` and `ImageDecode` signposts (`EntityUpdate` is now the main-thread part only: applying the changed entities);
  - clock and CPU.
  - `testFlickLiveTabs` flicks Home, Security and Climate on the live server (`TEST_RUNNER_FENTON_PERF_LIVE=1` plus credentials).
- **Physical device only.** Simulators report false hitch data, so the measured tests skip there. The smoke test `testEveryPageFlicksWithoutLosingContent` runs everywhere and is part of the normal journeys.
- **Running:** `tools/ios_perf.sh --device "<iPhone name>"`. Add `--live --env <temp.env>` for live pages, or `--only testFlickRecipes` for one page. Open the `.xcresult` in Xcode to read metrics and set baselines per device.
- **In the app:** Settings → Performance shows the same pages' hitch ratios from real use, plus MetricKit's daily scroll hitch ratio. Export Telemetry shares the JSON. See [telemetry](../../patterns/telemetry.md).
- **Targets (Apple):** hitch ratio under 5 ms/s is good, 5–10 is noticeable, over 10 is bad.
- **Adding a page:**
  1. Give its scroll view an identifier and `.scrollTelemetry("<Page>")`.
  2. Add a `Page` entry and a `testFlick<Page>` method.
  3. Add its launch to `tools/scrollcost-surfaces.txt`.
