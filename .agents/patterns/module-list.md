# Module list

> **What:** inset lists on the wallpaper (direction G, Controls: Lists). **Read when:** a page shows rows rather than tiles.

- `ModuleList { … }` puts rows on one `.module()` card with hairlines inset to the text (iOS 18+; flush rows on iOS 17). Use `.dense` when a row carries red or orange text.
- `ModuleRow(title, subtitle:, symbol:, glyph:, glyphOpacity:, showsChevron:) { accessory }`: a family-coloured glyph, the title and an optional subtitle (read as one element), then a trailing accessory (a state capsule, a pop-up menu). 52 pt tall, 60 pt with a subtitle; at accessibility sizes the accessory moves under the text.
- A row that does something is a `Button` around the row with `ModuleRowButtonStyle` (pressed highlight; disabled text never fades). Give the button the label, value and hint; hide a decorative accessory from VoiceOver.
- Unavailable rows dim only the glyph (`glyphOpacity: 0.5`), like tiles.
- Sheets don't use it: they use the system `Form`, whose dark grouped colours are G's sheet ground and cells.
- Users: Security's Doors and Mach-E lists, Climate's Thermostat Hub and Advanced Controls.
