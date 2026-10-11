# Food & Recipes: iPhone and iPad

> **What:** native Food implementation notes. **Read when:** changing `HassUI/Features/Food` or `HassCore/Recipes`.

- Service: `EverShelfRecipeService` (HassCore) over `HassConnection.callServiceWithResponse`, which sends websocket `call_service` with `return_response: true` and returns `response`. Parsing (`RecipeParsing`) ports `recipeTypes.ts`: snake or camel keys, loose numbers and flags, strict ingredient keys, bounded lists; an inconsistent group drops grouping rather than mis-grouping. Inventory reuses the transport.
- Routing: `FoodRoute` (`hub`, `recipes`, `inventory(location:)`) with `.foodNavigation()` on a `NavigationStack`; Home registers it, other lanes push `FoodRoute.hub`. Debug launch `FENTON_OPEN_FOOD=hub|recipes`. HIG: Navigation (push for hierarchy, sheet for a focused task).
- Hub: one column; two (suggestions + All Recipes, All Food + spaces) where `SplitPolicy` allows. The carousel is a paged `ScrollView` with page dots VoiceOver can adjust. HIG: Collections, Page controls.
- Recipes: `RecipeGrid` on `DynamicGridMetrics` (160 pt min, 2 to 8 columns) of `ImageCard`s; shared floating actions and `FilterSheet` ([floating-actions](../../patterns/floating-actions.md)). Results and hydration are announced. HIG: Searching, Sheets.
- Detail: a `.large` sheet with Done on single-page layouts; where a split is allowed (iPad landscape, unfolded Duo landscape) the trailing half shows it with Close, the open card is outlined and marked selected, and folding moves it into the sheet. Tabs are a segmented picker. Status text stays in primary ink; only icons carry color (contrast). HIG: Segmented controls, Split views.
- Symbols: Food maps its MDI names locally (`FoodSymbols`) instead of extending `SymbolMap`, whose duplicate keys crash at launch.
- Gallery: `FENTON_GALLERY=food`, `FENTON_GALLERY_ROUTE=hub|recipes`, `FENTON_GALLERY_FOOD_MODE=error|empty|slow`; 120 fixture recipes (every fourth Cookidoo), recorded calls in `gallery.lastCall`.
- Tests: `RecipeParsingTests`, `RecipeGroceryPolicyTests`, `RecipeFormattingTests`, `RecipeServiceTests`, `FoodConfigTests` (HassCore); `FoodModelTests`, `FoodViewTests` (HassUI); `FoodJourneyTests` (devices, audits, screenshots).
