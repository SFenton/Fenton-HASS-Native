# Dynamic grid

> **What:** the responsive tile grid. **Read when:** laying out tiles, cameras or quick links.

- One layout: `DynamicGridLayout(minCellWidth:maxColumns:spacing:)`. Column count is `floor((width + spacing) / (minCellWidth + spacing))`, clamped to `1...maxColumns`; leftover width is shared equally by all tracks.
- An unbounded proposal (an `HStack` probing a `maxWidth: .infinity` child, as the Food hub's landscape columns do) is treated like no proposal; `DynamicGridMetrics` with an infinite width returns `maxColumns` instead of trapping on `Int(.infinity)`.
- Items may claim more tracks with `.gridSpan(_:)`. An item never spans more columns than exist.
- Incomplete final rows align leading; never stretch a lone item to full width (web UX contract).
- **Equal row heights** (`equalRowHeights: true`): every tile row takes the tallest tile's height in the whole grid, so one wrapping title (Master Bedroom Closet on an iPhone) lifts every tile; tiles fill it inside `.equalHeightTiles()` (sets `tileFillsHeight`, read by `GlassTileFace`). A heading placed with `.gridHeader()` takes a whole row and keeps its own height, so one grid can hold several titled runs that share a height. Recomputed on every layout pass (Dynamic Type, rotation). Used by the room overview sheets.
- Camera grid: `minCellWidth` 160, `maxColumns` 4 (web `maxCellWidth={280} maxColumns={4}`).
- TODO(orchestrator): port the web's content-aware spans (`itemSizing="content-aware"`, `fillRows="except-last"`).
