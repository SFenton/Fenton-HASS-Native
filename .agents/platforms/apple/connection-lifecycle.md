# Connection lifecycle and caching

> **What:** how the app avoids reloads when reopened. **Read when:** touching the websocket, scene phase handling or the entity cache.

| Moment | Behavior |
|---|---|
| Cold launch | `EntitySnapshotCache` loads the last saved states from disk into `EntityStore` before the first frame, so Home draws real values immediately. `EntityStore.freshness` is `.snapshot(savedAt)` until the first live update |
| Connected | HAKit's `caches.states()` (`subscribe_entities`) delivers full state, then compressed diffs. `EntityStore.apply` updates only the boxes whose value changed |
| Background | The connection stays up for a grace period (`ConnectionLifecycle.backgroundGrace`, 30 s) so a quick app switch costs nothing, then disconnects. The snapshot is saved on entering background |
| Foreground | Reconnect; HAKit resubscribes and the store diffs the fresh full state in place. Views keep their identity and scroll position |
| Signed out | Disconnect, clear the store and delete the snapshot |

Rules:
- Never set a screen back to a loading state on reconnect. Show staleness with a quiet indicator, not by clearing content.
- The snapshot is written with `.completeUntilFirstUserAuthentication` protection and debounced (2 s) while live updates stream.
- Optimistic UI keeps its intent until the matching live state arrives or 8 s pass (web `CONTROL_REVERT_MS`).
