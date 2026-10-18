# Motion

> **What:** the shared components that apply the app-wide motion rules. **Read when:** you add any animation, navigation path, sheet, loading state or transition. The rules and their reasons live in [design/motion.md](../design/motion.md). Read that first.

Status: specified 2026-10-18. Being built on `claude/motion-system` (see PROGRESS.md). Until it lands, the rules in the design doc still apply to new code.

## Canonical components

| Component | Where | Does |
|---|---|---|
| `MotionTokens` | `HassDesign/Motion/MotionTokens.swift` | The only animation values: `quick`, `state`, `standard`, `emphasized`, `arrivalStagger`. Call sites never write a duration. |
| `.stateColorTransition(value:)` | `HassDesign/Motion/StateColorTransition.swift` | The only way a state-driven background, fill, tint, rim or ink colour animates: `MotionTokens.state`, scoped to the colour layer, Reduce Motion aware. Records itself in `MotionAudit` (debug and test) so tests can prove each component uses it. Every component and its status: [design/motion-components.md](../design/motion-components.md). |
| `MotionGallery` | `HassUI/Features/Gallery/MotionGallery.swift` | Every component with a state, with Toggle state and Toggle all, for visual checks and UX tests |
| `motionSafeAnimation(_:reduced:value:)` | `HassDesign/MotionSafeAnimation.swift` (exists) | Every implicit animation; Reduce Motion aware |
| `MotionPolicy` | `HassUI/App/Motion/MotionPolicy.swift` (`@Observable`, one per session, in the environment) | Remembers which moments have played this session (`hasPlayed(.signInArrival)`, `markPlayed`), and resets on sign-out. Exposes `reduceMotion`. Wraps measurement (`measure(.push(page))`). |
| `.arrivalMotion(_:index:)` | `HassUI/App/Motion/ArrivalMotion.swift` | Plays a moment's entrance for one view (fade and rise, staggered by `index`), only if the moment hasn't played this session and Reduce Motion is off. Otherwise it renders at once, or cross-fades under Reduce Motion. |
| `.zoomSource(id:in:)` / `.zoomDestination(id:in:)` | `HassUI/App/Motion/ZoomTransition.swift` | The iOS 18 zoom (`matchedTransitionSource` and `navigationTransition(.zoom)`); does nothing on iOS 17 |
| `NavigationTelemetry` | `HassUI/Diagnostics/NavigationTelemetry.swift` | Signposts for `TabSwitch`, `Push`, `Pop`, `SheetPresent`, `SheetDismiss`, `ZoomOpen`, `ZoomClose`, plus per-transition run-loop cost, feeding Settings → Performance |
| `ContentGate` | `HassDesign/Loading/ContentGate.swift` (exists) | The only content entrance for network-backed pages |
| `ArcSpinner` | `HassDesign/ArcSpinner.swift` (exists) | The only spinner |

## Rules for call sites
- **No raw animation values or transitions:**
  - no `.animation(_:)` without a value;
  - no `withAnimation(.easeInOut(duration:))` with literal timings;
  - no `.transition(...)` on navigation content.

  Use `MotionTokens` with `motionSafeAnimation` or `withAnimation(MotionTokens.x)`.
- **No entrance animations in `onAppear`** for content that came from `EntityStore` or a cache.
- **Tab switches and sheet-tab switches are cuts.**
- **Background colour changes always animate,** through `.stateColorTransition(value:)`. A new component, or a new state on one, gets a row in [design/motion-components.md](../design/motion-components.md), a unit test and a gallery entry in the same PR.
- **Zoom only for tiles that are what they open** ([design/motion.md §4.3](../design/motion.md)).
- **Every new navigation surface** gets its `NavigationTelemetry` interval and a row in `NavigationPerformanceTests`.

## Lint
`tools/lint_motion.sh` (run by `tools/apple_coverage.sh` and CI) flags:
- `.animation(` without `value:`;
- literal `duration:` outside `MotionTokens.swift`;
- `.transition(` in `HassUI/App` and `HassUI/Features` (allowed only for in-place view swaps, listed in the script's allowlist with a reason);
- `repeatForever` outside `ArcSpinner` and the pending pulse.

## Tests
- **Unit:** `MotionPolicyTests` (session memory, reset on sign-out, Reduce Motion paths) and `ArrivalMotionTests` (plays once, never on a second appearance, instant under the "already played" flag).
- **UX and accessibility** (iPhone, iPhone Duo, iPad), through the gallery or app:
  - a tab switch shows the destination's content in the first frame, with no opacity ramp;
  - the second Home appearance has no stagger;
  - the push and sheet still work with Reduce Motion on;
  - the zoom works on iOS 18 simulators and falls back on 17.
- **Perf:** `NavigationPerformanceTests` and `tools/ios_navperf.sh`, with budgets in [design/motion.md §10](../design/motion.md).

## Departures

None. Any exception (a page that should re-animate on revisit, a custom transition) needs the owner's approval and a line here, and in the design doc §3.
