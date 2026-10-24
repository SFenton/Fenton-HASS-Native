# Reconnecting and offline chip (component)

> **What:** How the shell signals a stale connection: the header arc (target), the offline chip, and today's orange chip. **Read when:** you touch ReconnectingArc, ReconnectingChip, OfflineChip or ReconnectingPolicy.

- Mockup: [reconnecting-chip.html](reconnecting-chip.html) · shipped (the "was" state shows the old chip) · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/App/Shell/ReconnectingArc.swift`, `ReconnectingIndicatorHost.swift`, `OfflineChip.swift`, `OfflineOverlay.swift`, `apple/Sources/HassCore/Connection/ReconnectingIndicator.swift`, `ReconnectingPolicy.swift`
- Spec: `.agents/design/direction-g.md`, `.agents/design/motion.md`, `.agents/platforms/apple/connection-lifecycle.md`, .agents/design/reconnecting-spinner.md · Patterns: motion
- States covered: arc, offline, was, reduce-motion, timeline, ax5, swatches
- Motion: arc fade 0.35 s, arc turn 0.82 s, dot breathe 1.4 s, chip enter 0.3 s; three transitions
- Devices: iPhone, folded Duo, iPad portrait
- Open notes: Read from the branch worktree (read-only). The catalog hint "10 pt move" is not what the code does (move(edge: .top), about the chip's height). Arc position on the Duo rail is still to confirm on a simulator.
