# Agent knowledge router

> **What:** the entry map for `.agents`. **Read when:** always, right after [AGENTS.md](../AGENTS.md); jump straight to the one file your task needs.

## By task

| Task | Read |
|---|---|
| Port or change a page | [pages/README.md](pages/README.md) → `pages/<id>/spec.md` + your platform file; procedure: [skills/port-page](skills/port-page/SKILL.md) |
| Add or change a control | [skills/add-control](skills/add-control/SKILL.md) |
| Touch shared behavior (grids, tiles, chips, sheets) | [patterns/README.md](patterns/README.md) |
| A design choice the owner hasn't made | [skills/design-decision](skills/design-decision/SKILL.md) |
| Fix a reported issue | [skills/fix-reported-issue](skills/fix-reported-issue/SKILL.md) |
| Sign-in, tokens, Keychain | [platforms/apple/auth.md](platforms/apple/auth.md) |
| Websocket, backgrounding, caching | [platforms/apple/connection-lifecycle.md](platforms/apple/connection-lifecycle.md) |
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
