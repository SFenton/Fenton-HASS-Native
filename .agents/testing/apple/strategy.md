# Test strategy and phases

> **What:** which tests to write at which maturity, and what certification requires. **Read when:** deciding what to test for your change.

## Phases

| Phase | When | What |
|---|---|---|
| Build | Every commit | `swift build --build-tests` and the iOS app build |
| Unit | As you go | Tests for new non-UX logic (`HassCore`, policies); run only new or changed tests while iterating |
| UX tests | Every UI fix or feature, same PR | A hosted test (`apple/Tests/HassUITests`, macOS host) or an XCUITest journey that fails without the change |
| Accessibility tests | Every UI fix or feature, same PR | See below |
| Full audits | The app is complete | Whole-app audit sweeps per device family and accessibility setting |
| Screen-reader walkthroughs | After full audits | Scripted VoiceOver walkthroughs per page |

## Accessibility tests with every change

A PR that adds or changes a visible control, page, sheet, row, navigation or layout adds or updates an accessibility test on **each device family it affects** (iPhone, iPhone Duo, iPad) that would fail if accessibility regressed. A missing one is a **major** review finding. Pure logic, data or copy-only changes are exempt; say why in the PR.

| Concern | Assert |
|---|---|
| Name, role, value, state | Every interactive element has a real label, the right trait and its current state (toggled, selected, expanded) |
| Reading and focus order | Visual order, headings before content; decorative elements hidden |
| Target size | 44 pt minimum (allow 1 pt off-grid tolerance) |
| Text scaling | At AX5 text grows (> 1.35×), isn't clipped, and actions stay reachable |
| Motion, transparency, contrast | Reduce Motion / Reduce Transparency paths; rendered contrast ≥ 4.5:1 for text over materials or camera images |
| Keyboard (iPad) | New actions are reachable by keyboard |

Mechanisms: hosted tests in `HassUITests` for labels, traits and order; an XCUITest `performAccessibilityAudit()` journey in `apple/Apps/iOSUITests` for each new page and sheet. No blanket waivers and never a whole audit type.

## Certification gates (two, independent)

1. **Line coverage:** ≥ 95% logic (`HassCore`) and ≥ 90% UX (`HassDesign`, `HassUI`), measured from real LLVM reports by `tools/apple_coverage.sh` (`contracts/coverage-rules.json`). Never exclude handwritten code to pass.
2. **Device journeys:** every journey passes on iPhone, iPhone Duo and iPad (`tools/ios_uitest.sh`). An unavailable simulator or pose is a gap, not a pass.

Gates certify releases; they are not run on every slice. Workers run the device and accessibility tests they add or touch before merging and list them in the PR.
