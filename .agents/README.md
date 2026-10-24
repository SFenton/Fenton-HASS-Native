# Agent knowledge router

> **What:** the entry map for `.agents`. **Read when:** always, right after [AGENTS.md](../AGENTS.md); jump straight to the one file your task needs.

## By task

| Task | Read |
|---|---|
| Port or change a page | [pages/README.md](pages/README.md) → `pages/<id>/spec.md` + your platform file; procedure: [skills/port-page](skills/port-page/SKILL.md) |
| Add or change a control | [skills/add-control](skills/add-control/SKILL.md) |
| Touch shared behavior (grids, tiles, chips, sheets) | [patterns/README.md](patterns/README.md), then [audit/README.md](audit/README.md) for known duplicates |
| Restyle a screen, tile, chip, sheet or spinner | [design/direction-g.md](design/direction-g.md), build order in [design/direction-g-plan.md](design/direction-g-plan.md) |
| The app icon or its alternates (Settings → App Icon) | [design/direction-g.md](design/direction-g.md) (App icon); regenerate the PNGs with `tools/render_app_icons.sh` |
| Any visible change (before code): mockups and a proposal for the owner | [workflow/propose-first.md](workflow/propose-first.md), mockups in [design/mockups](design/mockups/README.md) |
| A design choice the owner hasn't made | [skills/design-decision](skills/design-decision/SKILL.md) |
| Write or review SwiftUI | [.claude/skills/swiftui-pro](../.claude/skills/swiftui-pro/SKILL.md), applied per [workflow/swiftui-pro.md](workflow/swiftui-pro.md) |
| Fix a reported issue | [skills/fix-reported-issue](skills/fix-reported-issue/SKILL.md) |
| Report an Issue form, the request repo, the triage agent | [pages/settings/feedback.md](pages/settings/feedback.md), [workflow/triage-agent.md](workflow/triage-agent.md) |
| Sign-in, tokens, Keychain | [platforms/apple/auth.md](platforms/apple/auth.md) |
| Websocket, backgrounding, caching | [platforms/apple/connection-lifecycle.md](platforms/apple/connection-lifecycle.md) |
| Location, Home/Away, device sensors | [platforms/apple/location.md](platforms/apple/location.md), screen: [pages/settings/location.md](pages/settings/location.md) |
| Push notifications, the notification service extension | [platforms/apple/push.md](platforms/apple/push.md) |
| The shared `mobile_app` registration (push, location, sensors) | [platforms/apple/mobile-app.md](platforms/apple/mobile-app.md) |
| Decide what tests to write | [testing/apple/strategy.md](testing/apple/strategy.md) |
| Run tests on iPhone, Duo, iPad | [testing/apple/devices.md](testing/apple/devices.md) |
| Edit these docs | [workflow/docs-conventions.md](workflow/docs-conventions.md) |

## By platform

| Form factor | Design | Architecture |
|---|---|---|
| iPhone | [design/apple/iphone.md](design/apple/iphone.md) | [platforms/apple/architecture.md](platforms/apple/architecture.md) |
| iPadOS | [design/apple/ipados.md](design/apple/ipados.md), [split-view.md](design/apple/split-view.md) | same |
| iPhone Duo | [design/apple/duo.md](design/apple/duo.md) | same |
| watchOS | [design/apple/watchos.md](design/apple/watchos.md) | same |

## Folders

| Folder | Holds |
|---|---|
| [workflow/](workflow/README.md) | How we work: change loop, doc rules |
| [design/](design/README.md) | Per-platform HIG decisions and screen classification |
| [platforms/](platforms/README.md) | Architecture, auth, connection lifecycle, build and run |
| [pages/](pages/README.md) | One folder per web route: `spec.md` + per-platform notes |
| [patterns/](patterns/README.md) | Cross-screen behavior with one canonical component each |
| [skills/](skills/README.md) | Repeatable procedures |
| [testing/](testing/README.md) | Test phases and tooling |
| [audit/](audit/README.md) | The 2026-10-13 duplication and SwiftUI Pro audit, with its dedup plan |
