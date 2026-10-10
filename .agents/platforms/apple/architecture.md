# Apple architecture

> **What:** how the Swift code is structured. **Read when:** adding Apple code or a shared component.

| Path | Contents |
|---|---|
| `apple/Sources/HassCore` | No UI. `Auth/` (login flow, Keychain, token manager), `Connection/` (HAKit wrapper, lifecycle), `Entities/` (`EntityState`, `EntityStore`, `EntitySnapshotCache`), `Config/` (entity IDs ported from the web) |
| `apple/Sources/HassDesign` | Tokens (`HassTokens`), `DynamicGridLayout`, `GlassTile`, MDI → SF Symbol mapping |
| `apple/Sources/HassUI` | `App/` (root, session, tabs), `Features/<Feature>/` |
| `apple/Apps/iOS`, `apple/Apps/watchOS` | App entry points |
| `apple/Tests` | SwiftPM tests for Core and Design |

Deployment: iOS/iPadOS 17, watchOS 10. Swift 6 language mode.

## Invariants

- Views never talk to HAKit. They read `EntityStore.entity(_:)` (an `@Observable` box per entity) and act through `HassConnection.callService`.
- Entity IDs live in `HassCore/Config`, ported with a citation to the web constant they came from.
- A view that shows one entity observes only that entity's box, so unrelated updates do not redraw it.
