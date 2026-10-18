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
- **Tile finish A/B** (`--section finish`, not part of `all`): the 300-tile grid with each `TileFinish` (`FENTON_TILE_FINISH=solid|tintedGlass`, tinted glass is the shipped default), and variants with a layer left out (`FENTON_TILE_FINISH_OMIT=sheen,rim`, Debug only). Run it after changing a finish token or layer. Numbers: direction-g.md, Tile finish.
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

## Round 3 (2026-10-17, `claude/perf-chores-settings`): Chores and Settings

Owner, iPhone 18 Pro, Release: Climate, Security, Home and room pages scroll smoothly; Chores and Settings do not. Both are real `List`s (UIKit collection views); the others are `ScrollView`s. iPhone 17 Pro simulator, iOS 27.0, optimized build, gallery fixtures (`FENTON_GALLERY=settings`, `FENTON_GALLERY=chores FENTON_GALLERY_CHORES=12`, a house as long as the real one).

**Measure A/B in one hold, alternating.** The same build read 862, 883 and 817 ms of main-thread time on Settings in three runs and 1294 and 1183 ms on the long Chores page in two, whatever else the Mac was doing (other lanes' simulators share its cores). A first "before and after" taken minutes apart showed a 13% gain and 14 against 48 turns over 8 ms that the alternating rounds did not reproduce. Run base and change back to back, three rounds, and compare the rounds, not the first run of each. One long simulator hold carrying every run (a queue of command files) beats a hold per run: the simulator gate was full for an hour at a time.

**Root cause: the header fade's scroll reader.** `HeaderEdgeFade` read the page's scroll offset with `onScrollGeometryChange`. SwiftUI observes scroll geometry through the view graph, so every frame of a scroll became a graph update for the whole page, whether or not the value it reads changed (the clamped value changes only in the first 40 points). Layer A/B (`--section layers`, `FENTON_PERF_DISABLE`): Settings 890 ms without nothing, 647 without the whole fade, 614 without both readers, 640 without only the scroll reader, 811 without only the mask, 827 without only the geometry readers; instructions per 1000 pt 200 M with it, 120 M without. Time Profiler on Settings: SwiftUI graph updates 23% of main-thread samples, 10% without; `_UIHostingView` work 23%, 9%. A `ScrollView` page pays this too (Climate profiles at 42% graph updates) but spreads it over fewer, bigger hosting views; a `List` page has little else to spend.

**Fix.** On iOS the fade reads the offset from UIKit: a probe in the page's background finds the page's vertical scroll view (the shallowest one about as wide as the page, so a sideways rail is passed over) and observes `contentOffset` with KVO, writing to SwiftUI only when the clamped, rounded value changes (`UIKitScrollOffset`, `ScrollOffsetProbe`; the value is `HeaderEdgeFade.trackedOffset`, unit-tested). Other platforms keep `onScrollGeometryChange`. Until the scroll view is found (the first layout) the fade rests at its at-rest state, which is the right look at the top of a page.

| Gallery fixtures, scrolling 8 s (3 alternating rounds) | main-thread time | p95 turn | instructions per 1000 pt |
|---|---|---|---|
| Settings | 862, 883, 817 ms to 724, 718, 558 ms (-17% to -32%) | 2.4 to 2.6 ms to 1.7 to 2.2 ms | 187 M to 165 M |
| Chores tab (short fixtures) | 1013, 1016, 994 ms to 859, 811, 804 ms (-15% to -20%) | 3.1 to 2.9 ms | 264 M to 183 M |
| Chores, long house | 1447, 1412, 1378 ms to 1297, 1097, 1194 ms (-10% to -22%) | 7.8, 7.5, 7.3 ms to 7.7, 6.8, 6.9 ms | 450 M to 390 M |

Live Settings read 683 and 848 ms before and 734 and 661 after (the live house adds noise, not signal). Live Chores could not be measured: the house has nothing overdue today, so the tab fits one 874 pt screen and the probe finds nothing to scroll (`content=870`). A phone with the real overdue list is the measurement that settles it (below).

**What did not move it** (A/B, same hold): the quick links header's `onGeometryChange` positions (now widths, below), the soft bottom scroll edge effect (`scrollEdge`), the glass buttons (`glassBar`), the mask half of the header fade (`fadeMask`, 9%), the backdrop (`backdrop`, about 10% on Settings, none on Chores), per-row `listRowBackground` against a background drawn in the row's own content, and the per-row clip mask in `ModuleRowBackground` (now a shape fill; free on the CPU, a layer less on the GPU). The simulator cannot show GPU cost.

**What is left on the long Chores page, and not ours.** Time Profiler, 2,493 main-thread samples: 55% inside `UICollectionView`, of which `_createPreparedCellForItemAtIndexPath` is 24% and the self-sizing pass it triggers (`preferredLayoutAttributesFitting` → `ViewGraphRootValueUpdater._sizeThatFits`) 16%; 12% is `UINavigationController` observing the content scroll view for the large title; `TodoItemRow.body` itself is 2%, and everything of ours together is 3% (73 samples). A row that scrolls in is a new hosted cell, sized and built by SwiftUI and UIKit: 32 to 57 turns over 8 ms in 16 s of 900 pt/s scrolling, where a `ScrollView` page keeps its views. The levers left are fewer modifiers per row and fewer rows built at once, not anything on the page's own work. `Budget.longListP95` (8.0) and `longListTurnsOver8` (70) hold the line.

**Quick links alignment** (`AlignedToListMargins`) compared positions in the list's coordinate space: `frame(in: .named(...)).minX` on the header and on every plain row (section headers, spinners, errors), read on every frame because the row's frame moves with the scroll, through a closure put in the environment on every evaluation of the page. It compares widths now (a header is set in from both edges by the same amount, so the inset is half the difference of the two widths: `TodoRowMetrics.headerInset`, unit-tested), held in an `@Observable` the page owns, so only the header re-renders when a row reports. It did not move the numbers (the rule below was already in this file), and the journey for the alignment is unchanged.

**On a phone (nothing here ran on the iPhone 18 Pro).** The GPU is the half the simulator cannot see, and the one most likely behind "not smooth" on a 120 Hz display. Release build, signed in, run twice and compare with `tools/scrollcost_report.py B.tsv --compare A.tsv`:

```bash
tools/ios_scrollcost.sh --device 00008160-00022D8230914036 --only "Live Chores,Live Settings" --label phone-r3
# One layer off per run; headerFade, fadeMask, glassBar, scrollEdge, backdrop (HassDesign/PerfSwitches.swift):
for layer in headerFade fadeMask glassBar scrollEdge backdrop; do
  tools/ios_scrollcost.sh --device 00008160-00022D8230914036 --only "Live Chores,Live Settings" --label phone-no-$layer --disable $layer
done
python3 tools/scrollcost_report.py apple/.build/scrollcost-phone-no-fadeMask.tsv --compare apple/.build/scrollcost-phone-r3.tsv
tools/ios_perf.sh --device 00008160-00022D8230914036 --live --env temp.env --only testFlickLiveTabs   # system hitch ratio
```

If `fadeMask` (a full-page offscreen mask) or `glassBar` / `scrollEdge` moves the phone's p95 or `over8` while the simulator's CPU does not, that is the GPU cost, and the next change is a cheaper fade (a band over the top of the page, not a mask over all of it).

## Round 4 (2026-10-17, `claude/backdrop-blur`): the wallpaper

Owner: "less blur on the background image. Get us closer to web." The wallpaper was already blurred once, not live (`HouseBackdropStore` rendered a 480 px copy with sigma 20 and the view stretched it to the window), so the change is the recipe, not the cost model: the blur is now rendered once in points at the window's pixel size (`BackdropRenderer`), the view draws the bitmap with no scale effect, and the Settings slider re-renders off the main thread ([page-backdrop](../../patterns/page-backdrop.md) R8, R9).

`tools/ios_scrollcost.sh --section backdrop` runs three pages with the wallpaper behind them (`FENTON_BACKDROP_FIXTURE=1`: the gallery draws the shell's backdrop store with a fixture photo). iPhone 17 Pro simulator, iOS 27.0, optimized build, one hold, three alternating rounds, before (`origin/main` plus the fixture hooks) then after:

| Page, scrolling 8 s | main-thread time | p95 turn | turns over 8 ms | instructions per 1000 pt |
|---|---|---|---|---|
| Settings, before | 892, 779, 844 ms | 2.85, 2.26, 2.35 ms | 2, 2, 2 | 191 to 193 M |
| Settings, after | 824, 784, 794 ms | 2.84, 2.65, 2.63 ms | 2, 3, 2 | 194 to 202 M |
| Grid of 300 tiles, before | 2554, 2321, 2259 ms | 5.96, 5.45, 5.32 ms | 2, 1, 0 | 656 M |
| Grid of 300 tiles, after | 2433, 2434, 2322 ms | 5.95, 5.61, 5.62 ms | 1, 1, 2 | 642 to 657 M |

No difference outside the run-to-run noise (a first run in a hold reads a bogus idle floor, so its instruction columns are left out). Living Room fits one screen on the fixture and has nothing to scroll. What the number cannot show is the GPU: the after path draws one bitmap per page (no blur, no material, no scale effect), as before; run the phone A/B (`--disable backdrop`) before judging scroll feel.

The render itself (`BackdropRenderer.render`, a 1024 x 684 photo, a 402 x 874 pt window at 3x, on the Mac's GPU): 5 ms at 0% (1206 x 2622 px), under 2 ms at 50% and 100% (302 x 656 px, a quarter of the resolution), always off the main thread. A slider drag renders as fast as renders finish, with 140 ms between them.

## Launch and sign-in (2026-10-17, `claude/signin-and-launch-motion`)

What the launch intro, a signed-in relaunch and the sign-in arrival cost, measured the way scrolling is: a simulator's hitch ratio is false, so the number is the main thread's CPU time per run-loop turn (`MainThreadCostMeter`) plus the signpost intervals the run recorded. Motion design: [direction G, Launch and sign-in motion](../../design/direction-g.md#launch-and-sign-in-motion).

**Signposts** (`com.sfenton.home` / `Performance`, begun in one place and ended in another with `Telemetry.beginTracked` / `endTracked`; also records in the in-app log and Settings → Performance):

| Name | From | To |
|---|---|---|
| `Launch` | the `App` initializer | the first frame (`RootView`, after one turn) |
| `SnapshotShown` | the `App` initializer | the tabs' first appearance with the disk snapshot in the store (a signed-in relaunch; cancelled when signed out) |
| `SignIn` | Sign In pressed | Home Assistant hands back tokens |
| `Intro` | the intro's first animation | the form in place (≈1.2 s) |
| `Arrival` | tokens in hand | the end of the arrival animation (0.9 s of motion plus the build of Home) |
| `Reconnect` | the socket starts or fails | it is live again (cancelled when closed on purpose) |

**Probe and script.** With `FENTON_LAUNCHCOST=1` the app measures three phases by itself (`LaunchCostProbe`) and appends `LAUNCHCOST<TAB>phase<TAB>key=value…` to `FENTON_LAUNCHCOST_FILE`: `intro` (the two seconds after the first frame of a signed-out launch), `snapshot` (the same, signed in), and `arrival` (the animation, after `arrival-build`: tokens to Home built behind the sign-in layer, which is one long turn). `FENTON_AUTOSIGNIN=1` signs in with the prefilled credentials so no test drives the app. **Run it:** `tools/ios_launchperf.sh --env temp.env [--only intro,arrival,snapshot] [--no-budget]` (simulator only, inside devcap holds; builds `-O` like the scroll cost run; `apple/.build/launchperf-<label>.tsv`, table by `tools/launchcost_report.py`, which exits 1 on a missed budget). Never run it on a phone without the owner's say-so.

**Tests** (`Apps/iOSUITests/LaunchPerformanceTests.swift`; cost tests need `TEST_RUNNER_FENTON_PERF_ON_SIMULATOR=1`, so the normal journeys never run them):
- Metrics (baselines per device in Xcode): `XCTApplicationLaunchMetric` plus the `Launch` and `SnapshotShown` interval metrics (`XCTOSSignpostMetric`) for a cold signed-out launch, a launch with the intro off, and a warm signed-in relaunch.
- Budgets read from the probe's label (`diagnostics.launchcost`): intro (and the Reduce Motion intro), warm relaunch to the snapshot, and the arrival.
- Hitch ratios (`XCTHitchMetric`, iOS 26) for the intro and the arrival run **on a physical device only** and skip on a simulator, like `FastScrollPerformanceTests`; the target is under 5 ms/s. Device runs need the owner's say-so.
- Unit: `TrackedIntervalsTests`, `LaunchCostProbeTests`, `ReconnectingPolicyTests`, `RememberedAccountTests`; hosted: `LoginTests` (model, screen, flows, root choreography).

**Budgets (simulator).** p95 run-loop turn ≤ 8 ms everywhere; no turn over 16 ms while only the intro runs; `Intro` ≤ 1500 ms; `SnapshotShown` ≤ 500 ms (400 ms on an idle Mac); `Arrival` ≤ 1600 ms; the arrival and snapshot phases are held to a worst turn of 300 ms for the reason below.

**Baselines** (iPhone 17 Pro simulator, iOS 27.0, optimized build, beside four other lanes' simulators and builds, 2026-10-17; two runs of the arrival, one of the rest):

| Case | p95 turn | worst turn | turns over 8 / 16 ms | main thread, window | Interval |
|---|---|---|---|---|---|
| Intro (2.1 s window) | 0.5 ms | 3.1 ms | 0 / 0 | 47 ms | `Intro` 1222 ms; `Launch` 329 ms |
| Intro, Reduce Motion | 0.4 ms | 0.6 ms | 0 / 0 | 18 ms | `Intro` 392 ms (the 0.35 s cross-fade) |
| Arrival, build (tokens to Home built) | one long turn, not metered (the sign-in callback's turn) | | | 551 ms | `SignIn` 523 ms (real server) |
| Arrival (0.9 s window) | 5.5 ms | 227 ms | 5 / 2 | 369 ms | `Arrival` 1506 ms |
| Warm relaunch, signed in (2 s window) | 1.7 ms | 183 ms | 5 / 2 | 376 ms | `SnapshotShown` 425 ms; `Launch` 953 ms |

**Finding: Home's own first layout is a 180 to 230 ms turn.** The two long turns in the arrival and the snapshot windows are not the motion: a signed-in relaunch has no motion at all (the launch ground fades in 0.2 s) and has them too, while the intro and the Reduce Motion intro, which are nothing but motion, peak at 3.1 ms. The sign-in callback's turn also builds the whole signed-in tree (551 ms of main-thread time before the first animation frame, in one turn, behind the "Signing In…" arc). Both are Home's startup, not the motion; which part of it (the tabs, the camera tiles, the weather card are the likely ones) was not profiled here. It is the next performance lane's to find with Time Profiler, and the budgets hold the present worst turn rather than bless it. The p95 turn of both windows is under a 120 Hz frame.

**What this does not show.** The simulator's compositor and GPU: whether the intro's glow (a full-screen radial gradient fading 0 to 1), the backdrop's fade and scale, and the launch ground's fade drop frames on the phone is the device hitch tests' question.

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
- **No SwiftUI observer on a scrolling page's offset.** `onScrollGeometryChange` (and `onScrollPhaseChange` with a state write) makes SwiftUI update the page's view graph on every frame, even when the value it reads does not change. Observe the scroll view's `contentOffset` from UIKit (`UIKitScrollOffset`) and write to SwiftUI when a clamped value changes. A/B anything that touches every page with `FENTON_PERF_DISABLE` in one alternating hold before believing a number.
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
