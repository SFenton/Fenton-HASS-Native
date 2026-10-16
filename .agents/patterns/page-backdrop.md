# Page backdrop

> **What:** the blurred photo of the house behind every page. **Read when:** a page sets its own background, or you touch `pageChrome()`.

Owner, 2026-10-13: "No background image (blurred) of the house like web? Image should also be consistent across pages. (Modals do not have background)". Web: `ha-sfenton-react-dash@9ac2a46:src/components/shell/AppShell.module.css` `.backdrop` and `.scrim`, the image Home Assistant serves at `/local/images/house.webp`.

## Rules

- **R1. One photo, one component.** `HassUI/Common/HouseBackdrop.swift`: `HouseBackdropStore` loads `<server>/local/images/house.webp` through `ImagePipeline` ([image-cache](image-cache.md): disk cache, revalidation, swaps in a changed photo), renders it blurred (480 px wide, Gaussian sigma 20, saturation 1.1; direction G) and keeps the render in `Caches/HouseBackdrop` (`house-blurred-g.png`; rename it whenever the recipe changes so an old render never shows under a new scrim). `AppSession` creates the store at sign-in, before the first signed-in frame, so a relaunch draws the cached render on its first frame (AGENTS.md "No reload on reopen").
- **R2. Every page, the same crop.** `pageChrome()` draws `HouseBackdrop` as the navigation container background. The photo fills the window (`backdropCanvas`, measured by `MainTabView`) and each page or split pane shows the part under its own frame, so pushes, tabs and splits all show one picture.
- **R3. Modals have none.** Sheets keep the system sheet background.
- **R4. Pages are transparent.** `pageChrome()` hides list backgrounds (`scrollContentBackground(.hidden)`); a page never paints an opaque full-page background of its own.
- **R5. Always dark (direction G).** The signed-in shell sets `preferredColorScheme(.dark)`. The photo is scaled 1.06 under a black scrim that runs 0.44 → 0.40 (28%) → 0.42 (50%) → 0.52 (75%) → 0.64 from top to bottom, over the base `#111723` (`HouseBackdropStyle`). The top third never drops below 0.40, because white titles and section headers sit there (0.18 measured 3.0:1 under a light iPhone sky). Gallery pages get the same backdrop from `ComponentGallery`. There is no light wash any more.
- **R6. Reduce Transparency** draws the plain base color with no photo.
- **R7. The canvas is the whole window.** `backdropCanvas` is measured by `MainTabView` from a view *inside* the safe area, as its size plus its safe-area insets (`BackdropCanvas.size`). Never measure it from an `ignoresSafeArea()` view: that measured the safe-area rect (402 x 778 on an iPhone 18 Pro) and the photo ended 96 pt short, so a band of plain base color showed under the tab bar and the home indicator on every tab root and pushed page (owner, 2026-10-16: "Blurred image does not take full phone space"). Every pixel of the window, corners and edge midpoints included, shows wallpaper. A new root that draws a backdrop reads `backdropCanvas`; it never measures the window itself.

## Tests

`Apps/iOSUITests/WallpaperJourneyTests.swift` (iPhone, folded Duo, iPad portrait and landscape): launches with `FENTON_BACKDROP_FIXTURE=1` (debug builds: `HouseBackdropStore.session(for:)` serves a bright synthetic photo from a throwaway folder, so wallpaper is tellable from the plain base whatever the house photo is), samples the four corners and four edge midpoints of a screenshot, and fails on any as dark as the base. It covers every tab root, Quick Links, a room page, Food and Media, each at the top and scrolled to the bottom, and Home after backgrounding the app and returning.

`Tests/HassUITests/HouseBackdropTests.swift` (URL, render, cached render across launches, one refresh per store, newest photo wins, with and without a photo, G's scrim stops, `BackdropCanvas` adds the insets, the fixture photo).
