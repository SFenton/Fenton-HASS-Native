# Media (iPhone and iPad)

> **What:** how the native Media page is built. **Read when:** changing `HassUI/Features/Media`.

- `MediaPageConfig` (`HassCore/Config/MediaPageConfig.swift`) holds the sections; each card is a `MediaRemoteDevice` plus the remote it opens, its span and off icon.
- `MediaScreen` pushes from Home Quick Links (`HomeRoute.media`). It owns one Music Room `MediaRemoteController`: the source tiles read `display(_:)` and run `tap(_:)` on it, and the Music Room remote opens on the same controller, so an optimistic source change shows on both (web `OptimisticActionStateBoundary`). Other remotes open on their own controller via `MediaRemoteSheet(config:store:caller:)` with `.mediaRemotePresentation()`.
- Lead tiles are `GlassTile(kind: .navigate)` and open their remote whatever the TV's state (the remote's power button turns it on). Source and script tiles are toggles (value On/Off) and disable while their entity is unavailable.
- Layout: sections in a `DynamicGridLayout` (min 340 pt, up to 3), tiles under the lead in a grid (min 140 pt, up to 4); both scale with Dynamic Type. Full-width push page in every pose; no split ([split-view](../../design/apple/split-view.md)). HIG: Layout, Buttons.
- Fortnite shows the controller icon: its artwork is bundled with the web app, not on the server (same gap as the remote's Apps tab).
- Tests: `MediaPageConfigTests` (cards, labels, every service call, optimistic source), `HomePagesViewTests` (renders, tile look), `HomePagesJourneyTests` (gallery `FENTON_GALLERY=media-page`: calls, remote opens, audits with AX5, screenshots).
