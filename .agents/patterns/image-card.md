# Image card

> **What:** a tappable card with a remote image, title and subtitle. **Read when:** showing recipes, products or other image-led items in a grid or carousel.

- One component: `HassDesign/ImageCard.swift` (web `RecipeCard`). `imageURL` loads first, `fallbackImageURL` on failure, then `placeholderSymbol` on the module. Images are decorative to VoiceOver.
- Direction G: the photo fills a 22 pt card (`ImageCard.cornerRadius`, 1 : 0.78, `ImageCard.aspectRatio`) and the caption is white (15 Semibold title, 13 subtitle at 86%) over a bottom black scrim reaching 80% at the foot, so it reads on a white plate. Loading placeholders use the same ratio and radius.
- The caption is the card's only accessibility element (label, value, hint, `.isButton`, default action), framed to the text: the button underneath is hidden from accessibility and takes the taps. A card-sized element that is mostly photo fails rendered-contrast sampling (audit item 12). Callers' identifiers and traits land on the caption.
- At accessibility text sizes titles are never truncated (`ImageCard.titleLines`), so callers must widen cards there: the Recipes grid uses 320 pt cells (one column on iPhone) and the hub carousel one column of two rows. Truncated titles fail the AX5 audit ("Text clipped"). At accessibility sizes the card is a row with a 72 pt thumbnail on a module, with the caption in primary and secondary ink.
- Selection (e.g. the recipe open in a split pane) is drawn by the caller as an accent outline plus `.isSelected`.
- Used by: Food hub carousel, Recipes grid. Inventory product cards should reuse it.
- `RemoteImage` never takes touches (`.allowsHitTesting(false)`): `.clipped()` clips drawing, not hit testing, so a fill-scaled photo that overflows its frame covers whatever sits next to it. A live recipe photo in the iPad sheet covered the General / Ingredients / Instructions picker above it and swallowed every tap (2026-10-12). Apply the same rule to any other fill-scaled image (camera tiles, remote art).
