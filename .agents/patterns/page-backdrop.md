# Page backdrop

> **What:** the blurred photo of the house behind every page. **Read when:** a page sets its own background, or you touch `pageChrome()`.

Owner, 2026-10-13: "No background image (blurred) of the house like web? Image should also be consistent across pages. (Modals do not have background)". Web: `ha-sfenton-react-dash@9ac2a46:src/components/shell/AppShell.module.css` `.backdrop` and `.scrim`, the image Home Assistant serves at `/local/images/house.webp`.

## Rules

- **R1. One photo, one component.** `HassUI/Common/HouseBackdrop.swift`: `HouseBackdropStore` downloads `<server>/local/images/house.webp` once per launch, renders it blurred (480 px wide, Gaussian sigma 18, saturation 1.04) and caches the render in `Caches/HouseBackdrop`. `AppSession` creates the store at sign-in, before the first signed-in frame, so a relaunch draws the cached render on its first frame (AGENTS.md "No reload on reopen").
- **R2. Every page, the same crop.** `pageChrome()` draws `HouseBackdrop` as the navigation container background. The photo fills the window (`backdropCanvas`, measured by `MainTabView`) and each page or split pane shows the part under its own frame, so pushes, tabs and splits all show one picture.
- **R3. Modals have none.** Sheets keep the system sheet background.
- **R4. Pages are transparent.** `pageChrome()` hides list backgrounds (`scrollContentBackground(.hidden)`); a page never paints an opaque full-page background of its own.
- **R5. Dark and light.** Dark mode follows the web: `brightness(0.76)` and the `rgba(3,6,10,0.08 → 0.42)` scrim over `#111723`. The web has no light theme; light mode washes the photo with white (62 → 72%) so dark text on it keeps its contrast.
- **R6. Reduce Transparency** draws the plain base color with no photo.

## Tests

`Tests/HassUITests/HouseBackdropTests.swift` (URL, render, cache across launches, one refresh per launch, both schemes).
