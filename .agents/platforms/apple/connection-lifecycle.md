# Connection lifecycle and caching

> **What:** how the app avoids reloads when reopened. **Read when:** touching the websocket, scene phase handling or the entity cache.

| Moment | Behavior |
|---|---|
| Cold launch | `EntitySnapshotCache` loads the last saved states from disk into `EntityStore` before the first frame, so Home draws real values immediately. `EntityStore.freshness` is `.snapshot(savedAt)` until the first live update |
| Connected | HAKit's `caches.states()` (`subscribe_entities`) delivers the full set on every change. `HassConnection.receive` diffs it against the previous delivery by `last_updated` and state, converts only changed entities, and `EntityStore.apply(_:removing:freshness:)` updates only their boxes (converting every entity per event cost whole frames while scrolling) |
| Background | The connection stays up for a grace period (`ConnectionLifecycle.backgroundGrace`, 30 s) so a quick app switch costs nothing, then disconnects. The snapshot is saved on entering background |
| Foreground | Reconnect; HAKit resubscribes and the store diffs the fresh full state in place. Views keep their identity and scroll position |
| Signed out | Disconnect, clear the store and delete the snapshot |
| At home | `LocalServerRoute` moves the websocket (and HAKit's REST calls) to Home Assistant's home network address. HAKit re-reads `connectionInfo` on every `connect()` and swaps the socket only when the URL changed, so the subscription, store and views stay put |

Rules:
- Never set a screen back to a loading state on reconnect. Show staleness with a quiet indicator, not by clearing content.
- The snapshot is written with `.completeUntilFirstUserAuthentication` protection, debounced (10 s) and encoded off the main thread while live updates stream; entering background saves synchronously.
- Optimistic UI goes through `OptimisticActions` ([optimistic-actions](../../patterns/optimistic-actions.md)): the intent shows until the matching live state arrives, the call fails, or the revert time passes.
- Pages that load asynchronously wait behind a [content gate](../../patterns/content-gate.md); a gate that starts ready never shows a spinner.

## Home network address (`LocalServerRoute`)

The public URL resolves to Cloudflare even at home, so every call left the house and came back: 40–65 ms per request against about 14 ms to Home Assistant's home network address (measured from the Mac on home Wi-Fi, 2026-10-15). The route uses the home address whenever it is safe to.

- **Finding it.** On every `connect()` and network change, browse Bonjour `_home-assistant._tcp` (1.5 s) and read the TXT record's `internal_url`. Use it only when the same record's `external_url` or `base_url` is the signed-in server's public URL, the address is private (RFC 1918, 169.254/16, IPv6 unique-local or link-local, or `.local`), and `GET /manifest.json` answers 200 within 1.5 s. Home Assistant's own `internal_url` setting is empty here; the TXT value is the address Home Assistant derives (`http://192.168.1.22:8123`).
- **Not any Wi-Fi.** The token goes to that address, so a café network posing as home must fail. The route also requires the TXT `uuid` (the instance id, only sent on the home network) to match a pinned id. It pins the id the first time it sees the advertisement while Home Assistant, in live states over the public TLS socket, says the signed-in user's `person` is `home`; until then it never probes. After pinning, the id alone decides, so presence lag can't let an impostor in. Pins live in `UserDefaults` per server.
- **Switching sockets.** `applyRoute()` calls HAKit `disconnect()` then `connect()`. Letting `connect()` swap sockets keeps the old socket's delegate, so its late close could tear down the new one.
- **One session.** `AppSession` is made once by the app delegate and handed to `RootView`. Made in `RootView.init`, SwiftUI rebuilt it dozens of times a minute and each copy opened its own socket (found on the simulator, 2026-10-15).
- **Leaving it.** Any network path change drops the home address at once, before looking again, and so does a socket failure (`waitingToReconnect`), so HAKit's retry goes to the public URL. Cellular never looks.
- **Identity stays public.** `HassServer.baseURL` is still the public URL: snapshot caches, push links, camera and image URLs, the settings web view, token refresh and the `mobile_app` registration and webhooks (location reports run from background zone events with no connection or route) use it unchanged. Only the websocket and HAKit REST requests move.
- **Plain HTTP.** Port 8123 serves HTTP only, so the bearer token travels unencrypted on the home Wi-Fi, as it does with the official app's internal URL. `NSAllowsLocalNetworking` permits HTTP to local names and addresses only. iOS asks for Local Network access the first time.
- **Tests.** Off for UI test launches (`FENTON_UITEST_RESET`, `FENTON_HASS_TOKEN`, `FENTON_GALLERY`) unless `FENTON_LOCAL_ROUTE=1`; `FENTON_LOCAL_ROUTE=0` turns it off anywhere. Unit tests: `HassCoreTests/LocalServerRouteTests.swift`.
