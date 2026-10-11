# Status pill

> **What:** a read-only labeled value with a toned icon. **Read when:** showing a status value (battery, next run, connection) that is not a control.

- `StatusPill(label:value:detail:symbol:tone:)` (`HassDesign/StatusPill.swift`, web `src/components/core/StatusPill.tsx`). Tones: neutral, ok (green), active (water), warning (orange), danger (red), unavailable (gray); the tone colors the icon only, text stays `HassTokens.Ink`.
- One accessibility element: label, then "value, detail". Not a button; never put an action on it (use `GlassTile`).
- Lay pills out in a `DynamicGridLayout` (about 150 pt minimum, scaled with Dynamic Type) so they wrap at large text sizes.
- First used by Sprinklers.
