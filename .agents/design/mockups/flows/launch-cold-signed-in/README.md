# Cold launch, signed in (flow)
> **What:** the plain launch ground fading (0.2 s) onto the saved Home, then live values arriving in place; no intro, no spinner. **Read when:** you change the launch, snapshot or connection-lifecycle behaviour.
- Mockup: [launch-cold-signed-in.html](launch-cold-signed-in.html) · status shipped (the arc frame is in flight) · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/App/RootView.swift`, `MainTabView.swift`, `AppSession.swift`, `App/Shell/ReconnectingOverlay.swift`, `ReconnectingChip.swift`
- Spec: `.agents/platforms/apple/connection-lifecycle.md`, `.agents/design/motion.md`, `.agents/design/direction-g.md` · Patterns: resume-lifecycle, content-gate, motion
- States covered: launch ground, ground fading, snapshot shown, first-run pending bars, reconnecting after 2 s (arc, and today's chip), offline, live, AX5
- Motion: ground fade (quick), reconnecting arc (in flight), chip (main), pending pulse; transitions ground to saved screen, snapshot to live
- Devices: iPhone, Duo folded and unfolded, iPad
- Open notes: the arc is on `claude/reconnecting-spinner` (not main); the first-run state really follows a first sign-in; direction-g's first-sign-in spinner vs motion.md's soft bars (motion.md drawn)
