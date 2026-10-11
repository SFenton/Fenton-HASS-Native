# Info box

> **What:** a tinted notice with a title and optional message. **Read when:** a page shows a confirmed state or an informational banner.

- Canonical component: `HassDesign/InfoBox.swift`. Web: `src/components/core/InfoBox.tsx`.
- Tones: `.success` (green, only for a state Home Assistant has confirmed) and `.neutral` (gray). Text stays in the primary label color on a 16% wash of the tone, so it keeps 4.5:1 in light and dark; the icon carries the tint.
- One accessibility element (title and message combined).
- Consumers: Solo Trip "<Traveler> Away" notice.
