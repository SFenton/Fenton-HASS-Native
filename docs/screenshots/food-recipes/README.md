# Food & Recipes screenshots

Debug gallery (`FENTON_GALLERY=food`, fixture recipes; nothing reaches the house), captured from the host with
`FENTON_REDACT_PRIVATE=1` by `FoodJourneyTests` in screenshot passes (`TEST_RUNNER_FENTON_SKIP_AUDIT=1`), 2026-10-12.
Live-server screenshots are not committed.

| Layout | Folder | Notes |
|---|---|---|
| iPhone 17 Pro, portrait | `iphone-portrait/` | |
| iPad Pro 11-inch, portrait | `ipad-portrait/` | `*-ipad-landscape.png` here come from the rotate-in journey |
| iPad Pro 11-inch, landscape | `ipad-landscape/` | Split: the recipe opens in the trailing pane |
| iPhone Duo, folded | `duo-folded/` | `*-duo-landscape.png` here: folded never splits, the sheet stays |
| iPhone Duo, unfolded landscape | `duo-unfolded-landscape/` | From an earlier build (before the tile, placeholder and empty-state fixes) |
| iPhone Duo, unfolded portrait | — | Pending: Device Hub (fold/unfold) was down |

Pages: `food-hub-*` (hub; `-spaces` scrolled to the inventory tiles), `food-recipes-*` (grid), `-sort` / `-filter`
(sheets), `food-recipe-general|ingredients|instructions-*` (detail tabs), `food-recipe-cookidoo-*` (Cookidoo link-out),
`food-recipes-error|empty-*`, and `*-ax5` at the largest accessibility text size.

`evidence/filter-sheet-reset-ipad-portrait*.png`: the Filter sheet scrolled to Reset to Defaults on iPad portrait at the standard size and at AX5 (FilterSheet edfc05b), the pages behind the audit finding reported to PR #9 on 2026-10-13.
