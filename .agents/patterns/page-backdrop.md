# Page backdrop

> **What:** the blurred photo of the house behind every page. **Read when:** a page sets its own background, or you touch `pageChrome()`.

Owner, 2026-10-13: "No background image (blurred) of the house like web? Image should also be consistent across pages. (Modals do not have background)". Web: `ha-sfenton-react-dash@9ac2a46:src/components/shell/AppShell.module.css` `.backdrop` and `.scrim`, the image Home Assistant serves at `/local/images/house.webp`.

## Rules

- **R1. One photo, one component.** `HassUI/Common/HouseBackdrop.swift`: `HouseBackdropStore` loads `<server>/local/images/house.webp` through `ImagePipeline` ([image-cache](image-cache.md): disk cache, revalidation, swaps in a changed photo), renders it blurred (480 px wide, Gaussian sigma 20, saturation 1.1; direction G) and keeps the render in `Caches/HouseBackdrop` (`house-blurred-g.png`; rename it whenever the recipe changes so an old render never shows under a new scrim). `AppSession` creates the store at sign-in, before the first signed-in frame, so a relaunch draws the cached render on its first frame (AGENTS.md "No reload on reopen").
- **R2. Every page, the same crop.** `pageChrome()` draws `HouseBackdrop` as the navigation container background. The photo fills the window (`backdropCanvas`, measured by `MainTabView`) and each page or split pane shows the part under its own frame, so pushes, tabs and splits all show one picture.
- **R3. Modals have none.** Sheets keep the system sheet background.
- **R4. Pages are transparent.** `pageChrome()` hides list backgrounds (`scrollContentBackground(.hidden)`); a page never paints an opaque full-page background of its own.
- **R5. Always dark (direction G).** The signed-in shell sets `preferredColorScheme(.dark)`. The photo is scaled 1.06 under a black scrim that runs 0.36 → 0.18 (28%) → 0.36 (50%) → 0.50 (75%) → 0.64 from top to bottom, over the base `#111723` (`HouseBackdropStyle`). There is no light wash any more.
- **R6. Reduce Transparency** draws the plain base color with no photo.

## Tests

`Tests/HassUITests/HouseBackdropTests.swift` (URL, render, cached render across launches, one refresh per store, newest photo wins, with and without a photo, G's scrim stops).
