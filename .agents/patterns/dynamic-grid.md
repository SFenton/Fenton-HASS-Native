# Dynamic grid

> **What:** the responsive tile grid. **Read when:** laying out tiles, cameras or quick links.

- One layout: `DynamicGridLayout(minCellWidth:maxColumns:spacing:)`. Column count is `floor((width + spacing) / (minCellWidth + spacing))`, clamped to `1...maxColumns`; leftover width is shared equally by all tracks.
- Items may claim more tracks with `.gridSpan(_:)`. An item never spans more columns than exist.
- Incomplete final rows align leading; never stretch a lone item to full width (web UX contract).
- Camera grid: `minCellWidth` 160, `maxColumns` 4 (web `maxCellWidth={280} maxColumns={4}`).
- TODO(orchestrator): port the web's content-aware spans (`itemSizing="content-aware"`, `fillRows="except-last"`).
