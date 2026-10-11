# Fenton HASS Native: plan and progress

Single source of truth for what is being built, by whom and in which order. Update the lane table and log whenever work lands on `main`.

## 1. Operating model

Opus plans and reviews; Sonnet lanes implement in separate worktrees on disjoint folders; Haiku gathers. See [AGENTS.md](AGENTS.md#model-roles).

### Lanes and file ownership

A lane may read anything but only edit what it owns. Shared seams are orchestrator-owned; ask in your final report if you need a change there.

```
apple/Package.swift, apple/project.yml                    → orchestrator
apple/Sources/HassCore/Auth, Connection, Entities          → orchestrator (Core lane once opened)
apple/Sources/HassCore/Config/<Area>Config.swift           → the lane porting that area
apple/Sources/HassDesign/                                  → orchestrator (lanes may add new files)
apple/Sources/HassUI/App/                                  → orchestrator
apple/Sources/HassUI/Features/<Feature>/                   → the lane for that feature
apple/Sources/HassCore/Config/MediaRemote*.swift,
apple/Sources/HassCore/MediaRemote/,
apple/Sources/HassUI/Features/MediaRemote/,
apple/Sources/HassUI/Features/Gallery/MediaRemoteGallery.swift → media remote lane (claude/project-thread-go5jtz)
apple/Tests/**                                             → tests for your own files only
.agents/pages/<id>/, .agents/controls/<id>/                → the lane for that page/control
.agents/** (everything else)                               → orchestrator
```

## 2. Priorities

1. **Foundation (this scaffold):** sign-in, connection lifecycle, cached entity store, Home screen.
2. **Primary tabs:** Security, Climate, Chores, Settings, at web parity, iPhone first.
3. **iPad and iPhone Duo:** flyout navigation and on-demand split per [split-view](.agents/design/apple/split-view.md).
4. **Rooms and detail pages:** room pages, Food & Recipes, Groceries, vacuums, media.
5. **Live cameras:** snapshot tiles, then HLS, then WebRTC (go2rtc).
6. **Watch app:** glanceable status and a handful of controls.
7. **Report an Issue / Feature Request:** port from FestivalNativeApps with its own request repo.

## 3. Status

| Area | State |
|---|---|
| Sign-in (login flow, MFA step, Keychain) | Verified on the live server (password sign-in, relaunch skips sign-in) on iPhone, Duo and iPad |
| Connection lifecycle and entity snapshot cache | Scaffolded; unit tests for the cache and store |
| Home | Status rail, weather, guest presence, camera snapshots, lights sheet |
| Live cameras | Viewer plays WebRTC (go2rtc), falls back to HLS, then the snapshot; tiles stay snapshots |
| Security, Climate, Chores | Placeholders |
| Settings | Web link list (topics are placeholders), server status, Sign Out; splits on demand |
| Orientation policy (iPhone portrait, Duo/iPad free) | Scaffolded with unit tests |
| Split policy (landscape regular only) | `OnDemandSplitStack` built and verified on the Mac: divider at the exact midpoint on iPad landscape, on the hinge on the unfolded Duo landscape; rotation moves the open item between pane and push; Settings is the first adopter |
| iPad / unfolded Duo flyout | Built and verified on iPad and the unfolded Duo: overlay flyout in regular width, tab bar (folded Duo: vertical bar) in compact width |
| Test tooling | XCUITest journeys + audits on iPhone/Duo/iPad (`tools/ios_uitest.sh`); 95/90 coverage gate (`tools/apple_coverage.sh`), which now measures every test bundle: repo-wide 54.2% logic / 70.5% UX on 2026-10-11 (below the bars; the gaps are HassCore connection/Keychain, Login, the Home chip sheets and RootView/AppSession) |
| Media remote (sheet, 4 remotes, Hue Sync) | Shared component + debug gallery; not yet opened from a page (Rooms/Media lanes wire it) |
| Watch app | Target stub only |

## 4. Log

- 2026-10-10: initial scaffold.
- 2026-10-11: PR #1 verified on the Mac: journeys and accessibility audits green on iPhone, Duo (folded, unfolded portrait and landscape) and iPad; 32 `swift test` tests pass. Redacted screenshots in `docs/screenshots/pr-1/`.
- 2026-10-11: Lights sheet sends explicit `turn_on` / `turn_off` instead of `toggle` (Presence Based Lighting's Presence Lock reverts toggles in empty rooms), and dimmable groups get `BrightnessTile` (drag to set brightness, web `LightBrightnessCard`).
- 2026-10-11: media remote component (`.agents/patterns/media-remote.md`): config model and the four web remotes, optimistic overlay with revert timers, sheet with power, d-pad and Controls/Apps/Devices/Hue Sync tabs; unit, hosted and device journeys with audits.
- 2026-10-11: app navigation: regular-width overlay flyout (`App/Shell/`), `OnDemandSplitStack` with hinge-aware geometry, Settings list/detail split.
- 2026-10-11: PR #3 verified on the Mac. Fixed: the split never turning off after rotating to portrait (it measured its own fixed-width panes); the hinge not being read (read in `onGeometryChange`, inactive division while flat); content under the flyout still reachable by VoiceOver (UIKit tab controller hidden too); the full-window scrim winning the accessibility hit test over the rows; white-on-accent selected row (2.5:1); the edge strip eating taps, then the edge swipe also activating the control under it (now a UIKit screen-edge pan); a `DynamicGridLayout` crash on unbounded widths; the coverage script measuring one of three bundles. Redacted screenshots in `docs/screenshots/pr-3/`.
