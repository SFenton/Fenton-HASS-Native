# Apple accessibility audits

> **What:** audit rules and evidence (from FestivalNativeApps). **Read when:** writing the accessibility test a UI change ships with.

- Run XCTest `performAccessibilityAudit()` (all types). No blanket waivers and never a whole audit type. Accept a specific issue only with same-run evidence that disproves it (e.g. rendered contrast measured ≥ 4.5:1 from the screenshot), recorded here with the reason.
- Named visible text over camera images or materials gets a rendered-pixel contrast assertion (≥ 4.5:1 text, ≥ 3:1 meaningful edges); token math is not rendered evidence.
- Large text: assert real glyph growth (> 1.35× at AX5) and that actions stay reachable in every supported orientation.
- Never write `.accessibilityHidden(someBool)`: `false` on an ancestor un-hides descendants. Hide with a conditional modifier that only ever applies `true`.
- XCUITest cannot prove a SwiftUI view is hidden; assert hiding in a hosted test.
- iPad landscape: `XCUIScreen` returns the portrait panel buffer with orientation `.left`. `RenderedContrast` turns frames into it; never sample a landscape capture with screen coordinates (it measured unrelated pixels and both passed and failed elements, 2026-10-10). Exported attachments of that capture also look cropped; use the host capture (`FENTON_CAPTURE_DIR`) for review screenshots.
- Raise superscript text (units) with an `alignmentGuide`, not `baselineOffset`: the offset stretches the element's frame well past its glyph and the contrast audit judges the empty part (thermostat dial `°F`, iPad).
- XCUITest can only `adjust` slider elements, so a custom adjustable control (`accessibilityAdjustableAction`) is tested in the app-hosted `apple/Apps/iOSTests` bundle: host the view in a window, find the element by identifier and call `accessibilityIncrement()` / `accessibilityDecrement()`. SwiftUI publishes its tree there only with accessibility automation on (`_AXSSetAutomationEnabled`); without it a fresh simulator exposes nothing. Example: `ThermostatDialAccessibilityTests`.
- A single passing run of a flaky audit is not certification; a source-identical rerun must pass too.
- iPhone Duo: `XCUIDevice` cannot fold or rotate the Duo. Set the pose in Device Hub before the run; the journey audits the pose it finds.

## Accepted audit issues

`FentonHomeApp.audit` collects every issue in one run and accepts only these, all on system-drawn elements the app does not style:

| Issue | Element | Why |
|---|---|---|
| Contrast | Disabled buttons (e.g. Sign In before the fields are filled) | System dimmed style; disabled controls are exempt from WCAG 1.4.3 |
| Contrast | Text not fully inside the scroll view that holds it, or not hittable with nothing rendered at its frame (< 1.5:1): a chip scrolled behind the folded Duo's rail clip, a tile below a sheet's visible area, or text not fully inside the app window (the Hue Sync Brightness label below the iPad landscape sheet's edge measured 4.2:1 on its visible sliver, 2026-10-11) | Out of view: the audit samples it against what covers it. Seen on the folded iPhone Duo 2026-10-10; fully visible text is still checked |
| Dynamic Type "partially unsupported" | Text that is at least 1.35x taller when the same page is relaunched at AX5; an issue with no element only when every sampled text on the page grew that much. Only labels that name one content text on both pages are compared (bar titles are left out: they barely scale and can repeat a section header). The page check sums the sampled heights (together ≥ 1.35x, none shrank; the AX5 page is scrolled to find them): a grouped section header's frame carries fixed padding and grew only 40.3 → 52 pt at AX5 on 2026-10-10 | Known iPad false positive (FestivalNativeApps `dynamic-type-grows`); the AX5 relaunch is the evidence, measured in the same run |
| Contrast | Text whose own frame measures at least 4.5:1 in a capture from the same run (glyph upper quartile vs median surface, `RenderedContrast`) | The audit misjudges dark text on light materials, notably on iPad (FestivalNativeApps `IPadAuditRenderedContrast`); the failure message prints the measured ratio otherwise |
| Potentially inaccessible text, no element | Only while a sheet is up and Home's controls can't be hit (the sheet's dimming layer takes touches); for other pages, only while the control passed as `presenter` (Confirm Vacation: `vacation.modeCard`, Schedule Solo Trip: `soloTrip.toggle`) exists and can't be hit. Seen on iPad 2026-10-11 (3–4 issues, one per visible text of the page around the form sheet) | Home's text visible around an iPad form sheet is hidden from assistive technologies by the modal (FestivalNativeApps `requiresOutsideTree`) |
| Potentially inaccessible text, no element | Only when a confirmation popover (`PopoverDismissRegion`) was up as the audit started | The modal's text around the iOS 27 sign-out popover is hidden from assistive technologies by it; seen on the folded iPhone Duo 2026-10-11 (5 issues, none with an element) |
| Contrast, no element | The disabled Sign In button, only while `login.submit` is on screen and disabled | With `.dynamicType` or `.textClipped` in the same audit, this issue loses its element; probed per audit type on 2026-10-10, it is always the disabled button's |
| Contrast | `Form` section headers ("Home Assistant", "Two-factor code") | System secondary header style |
| Contrast | Text outside a confirmation popover's frame, only when `PopoverDismissRegion` was up as the audit started | iOS 27 anchors action sheets (Sign Out) as popovers; the audit samples covered text through the popover (measured 1.1–2.9:1 on 2026-10-10, iPhone); the audit itself can dismiss the popover, so it is noted first. The popover's own buttons stay checked |
| Contrast, Dynamic Type | Navigation bar buttons (a sheet's Done) | System Liquid Glass bar buttons; the audit samples them over the sheet's glass |

Add a row here and in `isSystemDrawn` together, with the evidence.

- `RenderedContrast` draws the screenshot through `UIImage` so the capture follows the interface orientation; the raw `CGImage` stays portrait in landscape and sampled the wrong pixels (every iPad landscape text measured ~1:1, 2026-10-11).

## Open findings

None yet.
