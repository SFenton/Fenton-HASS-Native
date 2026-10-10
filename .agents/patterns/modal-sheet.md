# Modal sheet

> **What:** how web hash modals become native sheets. **Read when:** presenting a modal.

- Web hash routes (`#lights-overview`) map to a `HomeSheet` enum driving `.sheet(item:)`. The URL hash is not needed natively.
- Detents: `.medium, .large` for lists of controls; `.large` for media. Drag indicator visible.
- A sheet that navigates (room → lights) pushes inside its own `NavigationStack` with Back, matching the web's in-sheet back.
