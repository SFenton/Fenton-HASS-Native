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
- **Tile finish A/B** (`--section finish`, not part of `all`): the 300-tile grid with each `TileFinish` (`FENTON_TILE_FINISH=solid|tintedGlass|frostedModule|webPort`), and variants with a layer left out (`FENTON_TILE_FINISH_OMIT=sheen,rim`, Debug only). Numbers: direction-g.md, Tile finish.
- **Tests:** `Apps/iOSUITests/ScrollSurfacesPerformanceTests.swift` holds the surfaces that were slow to a budget (`TEST_RUNNER_FENTON_PERF_ON_SIMULATOR=1`, and the token for the `testLive*` ones). Budgets, from the post-fix numbers: p95 turn 6 ms on fixtures and 3.5 ms live, no turn over 8 ms, none over 16 ms in the warm run, 25 ms of live-update work and 100 ms of main-thread time for a standing-still live page in 8 s.
- **Unit tests:** `MainThreadCostMeterTests` (the report), `HomeColumnsTests` (the scroll-invariant container), `EntityDeliveryOffMainTests` (deliveries cross to the main actor in order, a burst is diffed once).

### Found (2026-10-16, iPhone 17 Pro simulator, iOS 27.0, optimized build, live house)

**Applying live updates took over half of the main thread's CPU time.** HAKit sends the whole set of entities (thousands) on every change; its cache rebuilt a `Set` of them on the main queue, and `HassConnection.receive` rebuilt a dictionary of them and compared each to the last, also on the main thread. A Time Profiler trace of a page standing still: 1646 of 4113 main-thread samples (40%) in `HassConnection.delta`, another 624 (15%) in HAKit's cache transform. Nine milliseconds a delivery, four to seven deliveries a second: every delivery was a dropped frame at 120 Hz, on every page, scrolling or not. Fixed: HAKit's callback queue is now `HassConnection.deltaQueue`, so the cache, the diff and a burst's coalescing run off the main thread, and only the changed entities hop to the main actor ([connection lifecycle](../../platforms/apple/connection-lifecycle.md)).

| Live page, scrolling 8 s | main-thread p95 turn | longest turn | turns over 8 ms | live-update time on main |
|---|---|---|---|---|
| Climate | 6.1 → 1.8 ms | 85 → 8.4 ms | 26 → 0 | 398 → 0.2 ms |
| Recipes | 2.9 → 1.6 ms | 71 → 7.7 ms | 26 → 0 | 406 → 0.2 ms |
| Media | 3.0 → 1.8 ms | 144 → 7.9 ms | 25 → 0 | 442 → 0.3 ms |
| Theater Room | 3.1 → 1.8 ms | 91 → 6.9 ms | 19 → 0 | 276 → 0.2 ms |
| Chores | 3.0 → 1.6 ms | 50 → 6.8 ms | 26 → 0 | 346 → 0.6 ms |
| Living Room | 3.2 → 2.1 ms | 32 → 8.4 ms | 22 → 0 | 269 → 0.3 ms |
| Master Bedroom | 2.9 → 2.0 ms | 30 → 8.3 ms | 20 → 0 | 261 → 0.9 ms |
| Food hub | 2.3 → 1.8 ms | 29 → 6.5 ms | 19 → 0 | 279 → 0.2 ms |
| Pantry | 2.8 → 1.7 ms | 37 → 6.2 ms | 20 → 0 | 261 → 0.2 ms |
| Home, Security (after only) | 2.4, 2.3 ms | 9.3, 9.4 ms | 0, 0 | 0.2, 0.3 ms |

Before: `main` at 5ca163e with the probe added; after: the branch merged with `main`. Home and Security fit one 874 pt screen before `main` made the camera cards taller, so they have no before.

A page standing still (fixtures plus live updates): main-thread CPU in 8 s 439 → 3 ms (Living Room), 616 → 6 (Grid), 1562 → 5 (Climate), 787 → 7 (Chores); the 95th-percentile turn 18 to 49 ms → 0.05 ms. The updates' work did not vanish, it moved: process CPU is about the same (0.85 s in 8 s), on another core.

**Home scrolled with a state write per frame.** `HomeScreen` measured the space its content is offered with `frame(in: .global)` inside the scroll view, so the frame changed on every frame of a scroll and each change wrote `@State`, re-evaluating the page. It now keeps the horizontal position and the size only (`HomeColumns.container(from:)`, unit-tested). Not measured before and after: with the simulator's house state Home often fits one 874 pt screen (content 751 pt), so the probe finds nothing to scroll; the one run where it scrolled reads p95 2.0 ms and no turn over 8 ms. A phone run of `Live Home` settles it.

**What is left, and not ours to fix here.**
- Scrolling itself costs 0.5 to 0.65 s of main-thread CPU in 8 s on a static page (about 1.2 ms a frame, p95 1.5 to 2 ms live, 2 to 4 ms on fixtures), nearly all inside UIKit and SwiftUI: `UINavigationController` observing the content scroll view for the large title (`_observeScrollViewDidScroll`, 3% of the main thread's samples on the Grid and Recipes, 12% on a room page) and SwiftUI's attribute graph propagating the offset (`ScrollViewCommitMutation.apply` → `AG::Graph::propagate_dirty`). It grows with the number of views: about 1.6 M instructions per tile per 1000 pt (Grid of 300 tiles: 556 M per 1000 pt, p95 5.8 ms; Living Room about 40 tiles: 186 M, p95 3.7 ms; Climate: 138 M). `GlassTile`'s per-tile geometry observer was tried (removed for tiles without an accessory) and moved the Grid by 4%, so it is not the cause.
- **Camera streams** no longer keep running on a page with no camera: see Round 2 below.
- Sheets that fit one screen (most of them on a 874 pt phone: bed, wake light, purifier, remotes, Security System, Climate Advanced) have nothing to scroll; their cost is drawing when they open, which this probe does not read.
- Weather sheet: the rain is one 24 fps stroke now and stops when the app is not active; what is left of its idle cost is that timeline (Round 2).
- GPU cost: the simulator cannot show it. See below.

## Round 2 (2026-10-16, `claude/perf-pages-pass-2`)

iPhone 17 Pro simulator, iOS 27.0, optimized build, process CPU and main-thread time in 8 s. Before: `main` with the horizontal probe (`FENTON_SCROLLCOST_AXIS=horizontal` drives the widest sideways scroll view instead of the page).

| Surface | Before | After | What did it |
|---|---|---|---|
| Live Chores, standing still | process CPU 2850 ms | 312 ms | streams pause 4 s after no view in the selected section shows them |
| Live Climate, standing still | 3188 ms | 257 ms | same |
| Weather sheet, standing still | process CPU 829 ms, 1891 M instructions | about 520 ms, 560 M | one stroke per frame, timeline stops outside the active scene, the sheet's own presentation background is undecorated |
| Weather sheet, scrolling the page | main 1029 and 1046 ms | 789 to 868 ms | same, and the hourly row no longer commits through the page |
| Weather sheet, hourly row swiped | main 1133 and 1104 ms (the 370 ms of that is the rain) | 400 to 560 ms | `PagedRow`: the row pages in a UIKit scroll view |
| Food hub, Suggested Recipes swiped | main 982 and 998 ms, 3 and 0 turns over 8 ms | 705 to 736 ms with hosted paging, no gain against the page, see below | `CachedImage` and gate trims |
| Recipes, scrolling (fixtures) | main 1065 and 1141 ms, 2 and 2 turns over 8 ms, worst 16.3 and 8.4 ms | main 912 to 1109 ms, 0 to 3 over 8 ms, worst 14.4 to 15.9 ms cold and 8.0 to 9.6 warm | `itemAppeared`, `CachedImage` and gate trims; see below |

**Camera streams pause when nothing shows them.** The pool, not the views, decides ([camera streams](../../patterns/camera-streams.md)). The first version never fired: the tab bar keeps the other sections' views alive and does not call `onDisappear` when the tab changes (a 8 s idle run on Live Chores read the same 2.85 s as before), so `CameraLiveView` also watches `\.sectionIsShowing`. Home to Security keeps its stream because the pause waits 4 s and Security's tiles `appear` first (`testSecurityTilesShowTheStreamsHomeAlreadyHas`).

**The hourly weather row pages in UIKit.** The Weather sheet is a long page and the row was a SwiftUI `ScrollView` nested in it: every frame of a swipe committed through the sheet's view graph (the same cost the chip rail had, `.agents/patterns/status-rail.md`). `PagedRow` (`HassDesign/PagedRow.swift`) extends `HostedHorizontalScroll` with `UIScrollView.isPagingEnabled`: the hosted cells are `viewport / perPage` wide (the viewport is handed to the content through the environment), `firstVisible` is written once per page, and writing it pages the row (animated unless Reduce Motion). Accessibility is the hosted content's, as for the rail, and the keeps-`accessibilityEnabled` rule is unchanged. The row keeps its measured size between layouts: measuring the hosted cells took almost half of the busiest turns when something around the row re-laid out. The Home weather card uses the same component. **VoiceOver reads only the page on screen.** SwiftUI's `accessibilityHidden` on the other pages' cells does not reach UIKit from a hosted view (XCUITest still listed all 24 hours on iPad), so `HostedScrollView` overrides `accessibilityElements` and returns the hosted elements whose frames overlap its viewport (`PagedRowMetrics.indexes(ofFrames:overlapping:)`), pages with `accessibilityScroll(_:)` (a three-finger swipe goes a page, as a paging scroll view does) and posts `.pageScrolled` "Page 2 of 3" when the row settles on a page. `testCardSemantics` proves it on iPhone, iPhone Duo and iPad: the first page's hours are elements and hour 23 is not; after Next (wide layouts) or a swipe the first page's leave and the next page's are in. The spoken announcement still deserves one VoiceOver pass on a device. Two traps found on the way: a cell closure that reads this view's `@Environment` runs in the hosted graph and sees the default (read it before building the closure), and SwiftUI does not re-run closure-built content when only the closure's captures changed (the hosted root carries a revision through the environment).

**Where hosting does not pay: Suggested Recipes.** A hosted row pays for its own cells every frame (UIKit moves the hosting view, SwiftUI re-derives its transform: `_UIHostingView.updateTransform`, 17% of the main thread with 60 image cards in the row), where a nested `ScrollView` pays for the page around it. The hub is a short page of 60 image cards, so the two cost the same (hosted 850 to 970 ms against 982 ms), and a hosted page builds all of its cards at once, which hitched at every page crossing (11 to 19 turns over 8 ms in a sweep, worst 20 ms; building the neighbours only after the swipe settled, keeping built pages, skipping the re-root on a page change, and a smaller window each helped one number and left another). It stays a SwiftUI `ScrollView`. Rule: host a row when the page around it is long and the cells are light.

**Feedback attachments** were not measured: they sit in a short form sheet with a handful of thumbnails, so there is no page graph for a nested scroll to commit through; no change.

**Recipes is not under the 8 ms budget, and the card is not why.** A/B on one build with each layer of `ImageCard` switched off (photo, caption, scrim, fade, all three): no single layer moved main-thread time outside the run-to-run noise (about 5%), all three together took 28% off (1100 ms to 735 and 817), and with the card empty the first scroll after opening still has an 11.7 ms turn (a warm second sweep is 5.9 ms). That first turn is `LazyVGrid` placing the next rows: `LazySubviewPlacements.updateValue` → `HVGrid.lengthAndSpacing`, which measures each card (`sizeThatFits` through `ZStack`, `FlexFrame`, `Padding`) as it is placed. What was cheap to cut, was cut: `RecipeCollectionModel.itemAppeared` looked the card up in the whole list (O(N) string compares per card shown), now only the last `prefetchDistance`; `CachedImage` animated its fade with `withAnimation` around the state write, which put everything that changed in that update (the card around the photo) in an animating transaction (`AnimatableFrameAttribute` was 15% of the busiest turns), and now animates only its own subtree with `animation(value:)`; `contentReadiness` built three handlers per photo outside any gate (`ReadinessRequirement`), and now builds none. Together about 5 to 10% of the main thread while scrolling. What is left is SwiftUI's lazy grid on its first rows; a fixed card height would let it skip measuring but breaks Dynamic Type, so it was not tried.

**Weather rain.** Thirty-six `context.stroke` calls a frame became one stroke of one path, and the `TimelineView` is paused while the scene is not active. It already stopped for Reduce Motion (`WeatherBackdrop`'s `animated`). The sheet's presentation background (the colour that shows past the sheet's corners) was a second animated backdrop and is plain now. The rain itself is the largest part of the sheet's idle cost that is left (main-thread time at rest is still about 370 ms in 8 s: the timeline's 24 frames a second).

**The large-title tracking cost has no cheap native-preserving fix.** Time Profiler on Recipes: `UINavigationController _edgeInsetsForChildViewController` is 8.5% of the main thread's samples while scrolling, `UIKitNavigationController._observeScrollViewDidScroll` 2.4%, and resolving the content scroll view (`_resolveContentScrollViewForEdge`, a walk of the page's views on each pass) 2.5%. The options: an inline title (`navigationBarTitleDisplayMode(.inline)`) removes the tracking and the large title with it; `UIViewController.setContentScrollView(_:for:)` with the page's scroll view would save the walk (about 2.5%) but needs the scroll view found by UIKit lookup from SwiftUI, which is fragile; nothing in UIKit lets a large title collapse without observing the scroll. Left as is, documented here.

**Reproduce:** `FENTON_SCROLLCOST=1 FENTON_SCROLLCOST_AXIS=horizontal` (with `FENTON_GALLERY=weather FENTON_GALLERY_WEATHER_OPEN=1` or `FENTON_GALLERY=food FENTON_GALLERY_ROUTE=hub`); the camera numbers need the token and `FENTON_SCROLLCOST_OPEN=chores`. On a phone: `tools/ios_scrollcost.sh --device 00008160-00022D8230914036 --label phone-r2` (Live Chores and Live Climate for the camera pause, the Weather sheet for the rain) and compare with `--compare` against a run of `main`.

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
- **Chip rail:** `testSwipeChipRail` swipes Home's six-chip rail along a 120-tile page (`FENTON_GALLERY_PERF=chips`), device only like the others; `testChipRailSwipesWithoutLosingContent` runs everywhere. Set the baseline per device in Xcode.
- **Finding a nested-scroll cost on the simulator** (chip rail, 2026-10-16). Hitch metrics are false there, and `XCTCPUMetric` is dominated by XCUITest's accessibility snapshots (every variant measured the same), so profile instead: build Release with `SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) DEBUG'` (keeps the gallery), start the swipe test, `xcrun xctrace record --template "Time Profiler" --device <UDID> --attach <app PID> --time-limit 25s` (attach by PID: `--attach FentonHome` matches the UI test runner), `xctrace export --xpath '/trace-toc/run/data/table[@schema="time-profile"]'`, and count main-thread samples under `ScrollViewCommitMutation.apply`, `ViewGraphRootValueUpdater._updateViewGraph` and `CA::Transaction::commit`. Vary one thing at a time (tile count, chips, the header fade); a cost that grows with the *page* rather than the scrolled content means the scroll is writing into the page's view graph. Logging body evaluations (`NSLog` in `body`) shows whether a swipe re-renders anything.
