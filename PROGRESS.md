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
| Settings | Home Assistant settings modal (server, account, signed-in Settings/Profile web pages, Sign Out); household topics not ported |
| Orientation policy (iPhone portrait, Duo/iPad free) | Scaffolded with unit tests |
| Split policy (landscape regular only) | Policy and tests; split layout not built yet |
| iPad flyout | Not started (TabView for now) |
| Test tooling | XCUITest journeys + audits on iPhone/Duo/iPad (`tools/ios_uitest.sh`); 95/90 coverage gate (`tools/apple_coverage.sh`) |
| Media remote (sheet, 4 remotes, Hue Sync) | Shared component + debug gallery; not yet opened from a page (Rooms/Media lanes wire it) |
| Watch app | Target stub only |

## 4. Log

- 2026-10-10: initial scaffold.
- 2026-10-11: PR #1 verified on the Mac: journeys and accessibility audits green on iPhone, Duo (folded, unfolded portrait and landscape) and iPad; 32 `swift test` tests pass. Redacted screenshots in `docs/screenshots/pr-1/`.
- 2026-10-11: Lights sheet sends explicit `turn_on` / `turn_off` instead of `toggle` (Presence Based Lighting's Presence Lock reverts toggles in empty rooms), and dimmable groups get `BrightnessTile` (drag to set brightness, web `LightBrightnessCard`).
- 2026-10-11: media remote component (`.agents/patterns/media-remote.md`): config model and the four web remotes, optimistic overlay with revert timers, sheet with power, d-pad and Controls/Apps/Devices/Hue Sync tabs; unit, hosted and device journeys with audits.
- 2026-10-11: Home Assistant settings modal verified on the Mac (`claude/project-thread-4ttpvm`): the Settings web page opens signed in through the `localStorage.hassTokens` hand-off (no web login form). Settings journeys and audits pass on iPhone, Duo folded / unfolded portrait / unfolded landscape and iPad portrait / landscape; 52 `swift test` tests; new files ≥ 95% logic / ≥ 95.7% UX. `apple_coverage.sh` now measures every test bundle (repo-wide 63% / 61%, below the bars before this change too). Simulators under heavy host load crash backboardd at random; crashed journeys were re-run alone. Redacted screenshots in `docs/screenshots/ha-settings/`.
