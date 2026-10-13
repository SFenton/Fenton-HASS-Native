# Status rail

> **What:** the horizontal chip row under a page title. **Read when:** adding a summary chip.

- Chips come from config (`HomeConfig.statusChips`) with an entity, symbol, tone and the sheet they open. Pages pass their own subset to `StatusRail(chips:idPrefix:)` (Security shows Security and Contact Sensors).
- The rail scrolls horizontally; chips keep fixed widths so live values never shift neighbors.
- Each chip is a button with the label "<title>, <summary>" for VoiceOver and opens a sheet.
