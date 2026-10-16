# Fenton HASS Native: agent entry point

Read this file first, then [.agents/README.md](.agents/README.md) for the page, pattern, platform and test rules. For the current plan, lanes and file ownership read [PROGRESS.md](PROGRESS.md).

## Invariants

- **Native only.** SwiftUI for iOS, iPadOS and watchOS. No WebView UI, except the in-app Home Assistant settings modal (the backend's own config pages), which is a full-screen modal so the app stays usable underneath.
- **Home Assistant is the source of truth.** The app signals intent through one service call path (`HassConnection.callService`) and may show optimistic state only for immediate feedback. It never duplicates automation logic.
- **One state path.** Every entity read goes through `EntityStore`; every connection goes through `HassConnection` (HAKit). Do not open a second websocket or poll REST for state.
- **No reload on reopen.** Views bind to per-entity observable boxes in `EntityStore`, which updates them in place. A reconnect or a cold launch from the disk snapshot must never blank, re-fade or reorder a screen. See [connection-lifecycle](.agents/platforms/apple/connection-lifecycle.md).
- **Credentials.** Users sign in with username and password through Home Assistant's login flow ([auth](.agents/platforms/apple/auth.md)). Only the refresh token is persisted, in the Keychain. Never store the password, never commit a token, never ship a long-lived token in the app. `*.env` files are git-ignored.
- **Shared capacity.** Every simulator, physical device and heavy compile runs inside a `tools/devcap.py` hold (machine-wide FIFO slots shared with FestivalNativeApps): `python3 tools/devcap.py run --sim <UDID> -- <command>`. `tools/ios_uitest.sh` and `tools/apple_coverage.sh` already do. Never boot a simulator outside a hold. See [capacity](.agents/platforms/apple/capacity.md).
- **Pattern first.** A behavior that appears on more than one screen (grids, tiles, status chips, modal sheets, section headers) has one record in [.agents/patterns](.agents/patterns/README.md) and one canonical component. Extend it and sweep its consumers; never add a parallel implementation.
- **Apple design guidance.** Every UI decision goes through the Apple HIG (and the `apple-hig` skill where installed, including `/duo` for iPhone Duo). Cite the HIG section in the page or control note. HIG wins over web parity where they conflict; record the departure.
- **Web parity source.** The React dashboard `SFenton/ha-sfenton-react-dash` defines behavior and entity IDs. Read it; never edit it to make a native test pass. Cite files as `ha-sfenton-react-dash@<sha>:path:line`.
- **Shared code.** iPhone, iPad, Duo and Watch share `HassCore` and `HassDesign`; the phone and tablet share `HassUI`. Form-factor differences live in layout policies, not forked screens.
- **Devices (owner, 2026-10-10).** Every automation and accessibility test runs on iPhone, iPhone Duo and iPad. iPhone is locked to portrait. iPhone Duo and iPad rotate freely. Folded Duo, unfolded Duo portrait and iPad portrait are always single-page and never split; unfolded Duo landscape and iPad landscape may split. The rule is geometric (`SplitPolicy`), never a device-name check. See [split-view](.agents/design/apple/split-view.md).
- **Tests ship with the change (FestivalNativeApps rules).** Unit tests for new logic; with every UI change, a UX test and an **accessibility test** on each device family it affects (name/role/state, reading order, 44 pt targets, AX5 text scaling). A missing one is a major review finding. Certification needs **≥95% logic and ≥95% UX line coverage (owner decision 2026-10-16, raised from 90)** (`tools/apple_coverage.sh`) plus the device journeys (`tools/ios_uitest.sh`). See [testing](.agents/testing/apple/README.md).
- **SwiftUI Pro skill.** Every Swift change goes through [`.claude/skills/swiftui-pro`](.claude/skills/swiftui-pro/SKILL.md) (twostraws/swiftui-agent-skill v2.0.0, MIT): load it while writing SwiftUI and run it as a review (`/swiftui-pro`, or a focus such as `/swiftui-pro accessibility`) on your diff before you open a PR. The deployment target is iOS 17, so iOS 26/27-only rules apply only behind `#available` or when the target moves. Where it conflicts with these invariants or a pattern record, the repo rule wins; record the departure in the pattern doc. How we apply it: [workflow/swiftui-pro.md](.agents/workflow/swiftui-pro.md).
- Document Swift with DocC `///` and `// MARK: -` regions. Test behavior changes, not only compilation.

## Model roles

| Model | Role |
|---|---|
| Claude Opus 5.5 (xhigh) | Research lead and planner: identifies the work, writes specs and design decisions, and is the **sole final code reviewer**. Use sparingly. |
| Claude Sonnet 5.5 (high) | Implementation: code, tests, docs, skills and tools for work Opus has specified. |
| Claude Haiku 5.5 (medium) | Gathering: entity inventories, web-source lookups, screenshot capture, doc sweeps and other low-level work. |

## Change loop

1. Read the web source for the page or control and its spec (`.agents/pages/<id>/spec.md` + your platform file). Identify entities, states, services and navigation edges.
2. Implement in your lane's folders. Add unit tests for non-UI logic as you go, and a UI or accessibility test with each UI change.
3. Build, then run the journeys you added or touched on iPhone, iPhone Duo and iPad (`tools/ios_uitest.sh`) and check visually ([build-and-run](.agents/platforms/apple/build-and-run.md)).
4. Record durable findings as rules in the right `.agents` file, pattern doc first. Commit small cohesive commits and update PROGRESS.md.
