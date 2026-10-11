# Apple accessibility audits

> **What:** audit rules and evidence (from FestivalNativeApps). **Read when:** writing the accessibility test a UI change ships with.

- Run XCTest `performAccessibilityAudit()` (all types). No blanket waivers and never a whole audit type. Accept a specific issue only with same-run evidence that disproves it (e.g. rendered contrast measured ≥ 4.5:1 from the screenshot), recorded here with the reason.
- Named visible text over camera images or materials gets a rendered-pixel contrast assertion (≥ 4.5:1 text, ≥ 3:1 meaningful edges); token math is not rendered evidence.
- Large text: assert real glyph growth (> 1.35× at AX5) and that actions stay reachable in every supported orientation.
- Never write `.accessibilityHidden(someBool)`: `false` on an ancestor un-hides descendants. Hide with a conditional modifier that only ever applies `true`.
- XCUITest cannot prove a SwiftUI view is hidden; assert hiding in a hosted test.
- A single passing run of a flaky audit is not certification; a source-identical rerun must pass too.
- iPhone Duo: `XCUIDevice` cannot fold or rotate the Duo. Set the pose in Device Hub before the run; the journey audits the pose it finds.

## Accepted audit issues

`FentonHomeApp.audit` collects every issue in one run and accepts only these, all on system-drawn elements the app does not style:

| Issue | Element | Why |
|---|---|---|
| Contrast | Disabled buttons (e.g. Sign In before the fields are filled) | System dimmed style; disabled controls are exempt from WCAG 1.4.3 |
| Contrast | Text not fully inside the scroll view that holds it, or not hittable with nothing rendered at its frame (< 1.5:1): a chip scrolled behind the folded Duo's rail clip, a tile below a sheet's visible area | Out of view: the audit samples it against what covers it. Seen on the folded iPhone Duo 2026-10-10; fully visible text is still checked |
| Dynamic Type "partially unsupported" | Text that is at least 1.35x taller when the same page is relaunched at AX5; an issue with no element only when every sampled text on the page grew that much. Only labels that name one text on both pages are compared (a nav title can repeat as a section header). The page check sums the sampled heights (≥ 3 texts, together ≥ 1.35x, none shrank): a grouped section header's frame carries fixed padding and grew only 40.3 → 52 pt at AX5 on 2026-10-10 | Known iPad false positive (FestivalNativeApps `dynamic-type-grows`); the AX5 relaunch is the evidence, measured in the same run |
| Contrast | Text whose own frame measures at least 4.5:1 in a capture from the same run (glyph upper quartile vs median surface, `RenderedContrast`) | The audit misjudges dark text on light materials, notably on iPad (FestivalNativeApps `IPadAuditRenderedContrast`); the failure message prints the measured ratio otherwise |
| Potentially inaccessible text, no element | Only while a sheet is up and Home's controls can't be hit (the sheet's dimming layer takes touches) | Home's text visible around an iPad form sheet is hidden from assistive technologies by the modal (FestivalNativeApps `requiresOutsideTree`) |
| Contrast, no element | The disabled Sign In button, only while `login.submit` is on screen and disabled | With `.dynamicType` or `.textClipped` in the same audit, this issue loses its element; probed per audit type on 2026-10-10, it is always the disabled button's |
| Contrast | `Form` section headers ("Home Assistant", "Two-factor code") | System secondary header style |
| Contrast | Text outside a confirmation popover's frame, only when `PopoverDismissRegion` was up as the audit started | iOS 27 anchors action sheets (Sign Out) as popovers; the audit samples covered text through the popover (measured 1.1–2.9:1 on 2026-10-10, iPhone); the audit itself can dismiss the popover, so it is noted first. The popover's own buttons stay checked |
| Contrast, Dynamic Type | Navigation bar buttons (a sheet's Done) | System Liquid Glass bar buttons; the audit samples them over the sheet's glass |

Add a row here and in `isSystemDrawn` together, with the evidence.

## Open findings

None yet.
