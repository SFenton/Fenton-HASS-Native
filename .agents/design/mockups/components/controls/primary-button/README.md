# PrimaryButton and PrimaryButtonStyle (component)

> **What:** A screen's one primary action: 50 pt capsule, #0071E3 or an owner hue. **Read when:** adding a primary action or a custom label with the style.

- Mockup: [primary-button.html](primary-button.html) · shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassDesign/PrimaryButton.swift`, `PrimaryButtonStyle.swift`, `LoginView.swift`
- Spec: `.agents/design/direction-g.md` · Patterns: motion
- States covered: variants (default, family, long), disabled, pressed, busy, real usages, ax5; page and sheet surfaces.
- Motion: enable fade (quick), fill change (state), sign-in press scale 0.96.
- Devices: size class via the Device control.
- Open notes: Sign-in and Location labels belong to other batches; shown here for the press and busy looks.
- Shared helper: `pages/settings/_household-forms.js` (household-forms batch; local icons and builders, "promote to kit" in the notes).
