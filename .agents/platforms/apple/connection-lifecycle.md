# Connection lifecycle and caching

> **What:** how the app avoids reloads when reopened. **Read when:** touching the websocket, scene phase handling or the entity cache.

| Moment | Behavior |
|---|---|
| Cold launch | `EntitySnapshotCache` loads the last saved states from disk into `EntityStore` before the first frame, so Home draws real values immediately. `EntityStore.freshness` is `.snapshot(savedAt)` until the first live update |
| Connected | HAKit's `caches.states()` (`subscribe_entities`) delivers the full set on every change. `HassConnection.receive` diffs it against the previous delivery by `last_updated` and state, converts only changed entities, and `EntityStore.apply(_:removing:freshness:)` updates only their boxes (converting every entity per event cost whole frames while scrolling) |
| Background | The connection stays up for a grace period (`ConnectionLifecycle.backgroundGrace`, 30 s) so a quick app switch costs nothing, then disconnects. The snapshot is saved on entering background |
| Foreground | Reconnect; HAKit resubscribes and the store diffs the fresh full state in place. Views keep their identity and scroll position |
| Signed out | Disconnect, clear the store and delete the snapshot |

Rules:
- Never set a screen back to a loading state on reconnect. Show staleness with a quiet indicator, not by clearing content.
- The snapshot is written with `.completeUntilFirstUserAuthentication` protection, debounced (10 s) and encoded off the main thread while live updates stream; entering background saves synchronously.
- Optimistic UI goes through `OptimisticActions` ([optimistic-actions](../../patterns/optimistic-actions.md)): the intent shows until the matching live state arrives, the call fails, or the revert time passes.
- Pages that load asynchronously wait behind a [content gate](../../patterns/content-gate.md); a gate that starts ready never shows a spinner.
