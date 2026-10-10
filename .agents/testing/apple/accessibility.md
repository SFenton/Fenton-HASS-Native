# Apple accessibility audits

> **What:** audit rules and evidence (from FestivalNativeApps). **Read when:** writing the accessibility test a UI change ships with.

- Run XCTest `performAccessibilityAudit()` (all types). No blanket waivers and never a whole audit type. Accept a specific issue only with same-run evidence that disproves it (e.g. rendered contrast measured ≥ 4.5:1 from the screenshot), recorded here with the reason.
- Named visible text over camera images or materials gets a rendered-pixel contrast assertion (≥ 4.5:1 text, ≥ 3:1 meaningful edges); token math is not rendered evidence.
- Large text: assert real glyph growth (> 1.35× at AX5) and that actions stay reachable in every supported orientation.
- Never write `.accessibilityHidden(someBool)`: `false` on an ancestor un-hides descendants. Hide with a conditional modifier that only ever applies `true`.
- XCUITest cannot prove a SwiftUI view is hidden; assert hiding in a hosted test.
- A single passing run of a flaky audit is not certification; a source-identical rerun must pass too.
- iPhone Duo: `XCUIDevice` cannot fold or rotate the Duo. Set the pose in Device Hub before the run; the journey audits the pose it finds.

## Open findings

None yet.
