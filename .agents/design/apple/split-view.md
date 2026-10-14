# Screen classification and split view

> **What:** device orientation rules, when splits are allowed, and how each screen is presented. **Read when:** adding a screen or changing layout on iPad or iPhone Duo.

## Orientation and split rules (owner, 2026-10-10)

| Device / pose | Orientation | Split |
|---|---|---|
| iPhone | Portrait only (Info.plist `~iphone`) | Never |
| iPhone Duo folded (outer display) | Any (runtime, once a hinge is seen) | Never: single page |
| iPhone Duo unfolded portrait | Any | Never: single page |
| iPhone Duo unfolded landscape | Any | Allowed; divider on the hinge |
| iPad portrait | Any | Never: single page |
| iPad landscape | Any | Allowed; divider at the midpoint |

Implementation: `HassUI/App/Layout/SplitPolicy.swift` (regular width, wider than tall, each half ≥ 360 pt) and `OrientationPolicy.swift` + `DeviceSignals.swift` (ported from FestivalNativeApps). Never branch on a device name.

## On-demand split

From FestivalNativeApps `split-view.md`: a page starts full width; selecting an item splits it 50/50 at the content midpoint (Duo: the hinge) with the detail in the trailing half; Close or Back closes the trailing pane first; fold, unfold or rotation that disallows the split moves the open item onto the push stack, one run-loop turn after the window update, unanimated. No drawn divider (1 pt hairline only under Increase Contrast).

## Implementation

- `HassUI/App/Layout/OnDemandSplit.swift` — `OnDemandSplitStack(path:openItem:alwaysSplit:root:detail:placeholder:)` replaces a section's `NavigationStack`. It owns the leading stack and, where `SplitPolicy.geometry(container:isRegularWidth:hinge:)` returns pane widths, a trailing `NavigationStack` with **Close** (`split.close`, Escape) and container `split.trailing`. Without a split the same `openItem` is pushed on the leading stack (`navigationDestination(item:)`), so fold/rotation keeps the item; turning the split on or off applies one run-loop turn later, unanimated. Opening and closing spring (Reduce Motion: crossfade).
- Measure the space offered, not the panes: the container frame comes from a `frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)` around the `HStack`. Measuring the `HStack` kept the landscape width after rotating to portrait (its fixed pane widths), so the split never turned off and overflowed the window; a flexible frame without `minWidth: 0` still grows to its child.
- Geometry: the band is the Duo hinge when it crosses the container, else 1 pt at the container's midpoint; each pane ≥ 360 pt. `readsWindowHinge()` reports the active division (book pose), else the inactive one the system still reports while the inner display lies flat (`.includeInactive`), as FestivalNativeApps' `DeviceLayout.splitHinge` does, so the Duo splits on the hinge in every inner pose (owner, 2026-10-10). It reads in `onGeometryChange`; reading on appear and on size changes missed the regions, which arrive after the first layout. Measured on the iPhone Duo simulator, unfolded landscape (951 × 669 pt): hinge band 455.3–495.7 pt, leading pane ends at the band, trailing pane starts at 495.7 pt. Before this fix the flat Duo split at the midpoint of the space left of the system's vertical bar (434 pt). No drawn line except a hairline under Increase Contrast at a midpoint.
- Rows set `openItem`, mark the open row selected (`.isSelected`, accent row background).
- First adopter was Settings (`alwaysSplit`, placeholder `settings.placeholder`) until direction G moved Settings into the Account sheet (2026-10-14), where topics push. `OnDemandSplitStack` has no production adopter now; it stays, with its hosted tests, for the next list/detail page (chore lists, rooms).

## Screen classification

| Kind | Screens |
|---|---|
| Always full width, push | Home, Security, Climate, Chores, room pages, Food & Recipes |
| Split on demand (where allowed above) | Chores lists → item detail; Food hub → Pantry, Fridge, Freezer, Spice Rack, Cabinet; Recipes → recipe |
| Leading pane, detail on the right (where allowed) | Settings: list stays left, topic opens right, placeholder when nothing is selected |
| Sheet | Status chip sheets (lights/rooms, security system, climate, occupancy, contacts), light and climate controls, Daily Report, to-do edit |
| Full-screen modal | Camera viewer, Home Assistant backend settings (web view), sign-in |

The full screen map is the coordinator's dashboard inventory: https://claude.ai/code/artifact/bba4d82d-2e8f-4aee-b216-8256aa97f47c
