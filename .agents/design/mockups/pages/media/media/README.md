# Media (page)
> **What:** Every TV and media source in the house by room: the room's TV leads and opens its remote; sources and quick launches run in place. **Read when:** you change `MediaScreen`, `MediaPageConfig` or the media tiles.
- Mockup: [media.html](media.html) · status shipped · reviewed 2026-10-23
- Source: `HassUI/Features/Media/MediaScreen.swift`, `HassCore/Config/MediaPageConfig.swift`, `HassDesign/GlassTile.swift`, `DynamicGridLayout.swift` · Spec: `.agents/pages/media/spec.md`, `ios.md` · Patterns: entity-tile, media-remote, dynamic-grid
- States covered: default, loading (pending bars), refreshing, error (unavailable), offline, reconnecting (+ was), all-off, xbox-source, long-text, ax5, closed
- Motion: source tile on (state 0.6 s), lead fill, pending pulse; transitions: push from Quick Links, sheet to the remote
- Devices: iPhone, Duo folded, Duo unfolded landscape and portrait, iPad portrait and landscape (1, 2 or 3 section columns)
- Open notes: no empty state; the Apple TV is not on this page (web parity); reconnecting arc is in flight (claude/reconnecting-spinner); shared helpers in `components/media/_media-lights-cameras.js` (promote to kit)
