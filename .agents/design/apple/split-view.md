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

## Screen classification

| Kind | Screens |
|---|---|
| Always full width, push | Home, Security, Climate, Chores, room pages, Food & Recipes |
| Split on demand (where allowed above) | Chores lists → item detail; Food hub → Pantry, Fridge, Freezer, Spice Rack, Cabinet; Recipes → recipe |
| Leading pane, detail on the right (where allowed) | Settings: list stays left, topic opens right, placeholder when nothing is selected |
| Sheet | Status chip sheets (lights/rooms, security system, climate, occupancy, contacts), light and climate controls, Daily Report, to-do edit |
| Full-screen modal | Camera viewer, Home Assistant backend settings (web view), sign-in |

The full screen map is the coordinator's dashboard inventory: https://claude.ai/code/artifact/bba4d82d-2e8f-4aee-b216-8256aa97f47c
