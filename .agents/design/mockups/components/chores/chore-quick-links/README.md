# Chore quick links (counts) (component)
> **What:** the Quick Links section: five filled tiles with counts and subtitles, Groceries spanning the last row. **Read when:** you change the tiles, their colours or the count rules.
- Mockup: [chore-quick-links.html](chore-quick-links.html) · status shipped · reviewed 2026-10-23
- Source: `HassUI/Features/Chores/ChoresScreen.swift`, `TodoListAlignment.swift`, `HassDesign/{GlassTile,DynamicGridLayout,ColorFamily}.swift` · Spec: `.agents/pages/chores/spec.md`, `ios.md` · Patterns: entity-tile, dynamic-grid
- States covered: five tiles, 2, 3 and 4 tracks, zero counts, both viewers, non-resident, ax5
- Motion: none (tiles push; see the Chores page)
- Devices: iPhone, Duo, iPad (the Device control picks the size class)
- Open notes: a long title can touch the count numeral; ios.md departure text is out of date.
