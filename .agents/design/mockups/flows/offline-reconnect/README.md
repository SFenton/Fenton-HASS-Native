# Offline and reconnect (flow)
> **What:** how a dropped connection shows: nothing for 2 s, then the header arc (in flight) or today's Reconnecting chip, the offline chip at once with no network, values staying put. **Read when:** you change connection status UI or the reconnecting arc.
- Mockup: [offline-reconnect.html](offline-reconnect.html) · status in-flight:claude/reconnecting-spinner · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/App/Shell/ReconnectingOverlay.swift`, `ReconnectingChip.swift`, `Features/Settings/HomeAssistantSettingsView.swift`, `HassCore/Connection/ReconnectingPolicy.swift`
- Spec: `.agents/platforms/apple/connection-lifecycle.md`, `.agents/design/reconnecting-spinner.md`, `.agents/design/direction-g.md` · Patterns: resume-lifecycle, motion
- States covered: connected, down under 2 s, arc (target), chip (was), offline chip, stale values, live again, HA settings Connection row (reconnecting, offline, rejected), AX5
- Motion: arc in and out (0.35 s), chip in and out (standard, move from the top), dot breathing, values in place
- Devices: iPhone, Duo folded and unfolded, iPad
- Open notes: the arc is unmerged; the catalog says the chip moves 10 pt, the code's `.move(edge: .top)` moves it by its padded height; the offline chip covers the title at AX5
