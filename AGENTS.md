# Fenton HASS Native: agent entry point

Read this file first, then [.agents/README.md](.agents/README.md) for the page, pattern, platform and test rules. For the current plan, lanes and file ownership read [PROGRESS.md](PROGRESS.md).

## Invariants

- **Native only.** SwiftUI for iOS, iPadOS and watchOS. No WebView UI, except the in-app Home Assistant settings modal (the backend's own config pages), which is a full-screen modal so the app stays usable underneath.
- **Home Assistant is the source of truth.** The app signals intent through one service call path (`HassConnection.callService`) and may show optimistic state only for immediate feedback. It never duplicates automation logic.
- **One state path.** Every entity read goes through `EntityStore`; every connection goes through `HassConnection` (HAKit). Do not open a second websocket or poll REST for state.
- **No reload on reopen.** Views bind to per-entity observable boxes in `EntityStore`, which updates them in place. A reconnect or a cold launch from the disk snapshot must never blank, re-fade or reorder a screen. See [connection-lifecycle](.agents/platforms/apple/connection-lifecycle.md).
- **Credentials.** Users sign in with username and password through Home Assistant's login flow ([auth](.agents/platforms/apple/auth.md)). Only the refresh token is persisted, in the Keychain. Never store the password, never commit a token, never ship a long-lived token in the app. `*.env` files are git-ignored.
- **Pattern first.** A behavior that appears on more than one screen (grids, tiles, status chips, modal sheets, section headers) has one record in [.agents/patterns](.agents/patterns/README.md) and one canonical component. Extend it and sweep its consumers; never add a parallel implementation.
- **Apple design guidance.** Every UI decision goes through the Apple HIG (and the `apple-hig` skill where installed, including `/duo` for iPhone Duo). Cite the HIG section in the page or control note. HIG wins over web parity where they conflict; record the departure.
- **Web parity source.** The React dashboard `SFenton/ha-sfenton-react-dash` defines behavior and entity IDs. Read it; never edit it to make a native test pass. Cite files as `ha-sfenton-react-dash@<sha>:path:line`.
- **Shared code.** iPhone, iPad, Duo and Watch share `HassCore` and `HassDesign`; the phone and tablet share `HassUI`. Form-factor differences live in layout policies, not forked screens.
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
3. Build and check visually on the simulator ([build-and-run](.agents/platforms/apple/build-and-run.md)).
4. Record durable findings as rules in the right `.agents` file, pattern doc first. Commit small cohesive commits and update PROGRESS.md.
