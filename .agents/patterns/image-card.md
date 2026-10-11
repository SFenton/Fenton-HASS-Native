# Image card

> **What:** a tappable card with a remote image, title and subtitle. **Read when:** showing recipes, products or other image-led items in a grid or carousel.

- One component: `HassDesign/ImageCard.swift` (web `RecipeCard`). `imageURL` loads first, `fallbackImageURL` on failure, then `placeholderSymbol` on a tinted fill. Images are 4:3 and decorative to VoiceOver.
- The card is one button: title and subtitle read together, with `accessibilityHint` for what it opens. 44 pt minimum target.
- `reservedTitleLines` keeps rows of cards aligned when titles wrap (carousels pass 2). At accessibility text sizes titles are never truncated (`ImageCard.titleLines`), so callers must widen cards there: the Recipes grid uses 320 pt cells (one column on iPhone) and the hub carousel one column of two rows. Truncated titles fail the AX5 audit ("Text clipped"). At accessibility sizes the card is a row with a 72 pt thumbnail: with a full-width picture the card's frame is mostly image and fails the contrast audit. The placeholder symbol uses secondary ink (system gray on the gray fill is about 3:1).
- Selection (e.g. the recipe open in a split pane) is drawn by the caller as an accent outline plus `.isSelected`.
- Used by: Food hub carousel, Recipes grid. Inventory product cards should reuse it.
