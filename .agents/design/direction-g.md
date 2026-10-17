# Design direction G: native on the house

> **What:** the visual language for every page and sheet (owner choice, 2026-10-13: Apple system components on the blurred house photo, after rejecting custom looks as "very Android and too far removed from Apple"). **Read when:** building or restyling any screen, tile, chip, sheet or spinner.

Mockups of every screen live on the owner's private gallery (https://claude.ai/artifact/WucowN61kBaBEdLVTP6JFb); the HTML sources are in the project's shared folder, not this public repo. Owner decisions win over this file, and HIG *must* rules win over both. The build order is in [direction-g-plan.md](direction-g-plan.md).

## The idea

Fenton Home should look like Apple made it, with Apple Home and Apple Weather as the reference. Distinctiveness comes from three places:
- the house wallpaper;
- a few signature controls: the thermostat dial from main, the light dragger and the remote;
- putting cameras and climate up front.

It never comes from custom chrome, custom surfaces or a custom palette.

## Layers

| Layer | Look | Where |
|---|---|---|
| Wallpaper | The house photo (`/local/images/house.webp`), blurred 20, saturation 1.1, scaled 1.06, under a dark scrim. The scrim runs 0.44 → 0.40 (28%) → 0.42 (50%) → 0.52 → 0.64 from top to bottom; the top third stays at 0.40 or more so white titles and headers pass 4.5:1 over a light sky (2026-10-14 audit). Decode it once at screen size, blur it once and cache the bitmap; never run a live `.blur` per frame. | Every tab root and pushed page, on every platform. Never in sheets. |
| Modules on the wallpaper | `systemGray6` dark at 55% with a 30pt background blur (thin material); built as `#1C1C1E` at 66% with no live blur, because the wallpaper is already blurred and a backdrop layer per tile cost GPU time (and crashed the simulator's render server, 2026-10-14). 26pt radius, no rim or bevel, white text. A module that carries red or orange status text (overdue chores, expired food, an error tile) uses the denser `rgba(20,20,22,.78)` so that text stays readable over the lit windows. | Cards, inset lists and tiles on pages. These are content-layer materials and never `.glassEffect` (HIG must). |
| Sheets | System sheet in the **system appearance** (owner decision, 2026-10-15). Dark: `#1C1C1E` ground, `#2C2C2E` cells and tiles. Light: `#F2F2F7` ground (`systemGroupedBackground`), white cells and tiles (`secondarySystemGroupedBackground`), label ink. The presenting page scales back and dims. | Every modal, except the ones that are dark by design (below). |
| Liquid Glass | System glass. iOS 17–25 fall back to `.ultraThinMaterial` capsules. | Navigation only: the tab bar, the Quick Links circle, toolbar circles (Profile, Back, Close, Cancel, Save), bottom section controls and page bottom toolbars. |

Pages are always dark-styled because they sit on the dimmed photo, the way Apple Home's wallpaper works. Sheets follow the system appearance, like Apple's own sheets in Home, Settings and Reminders (HIG: Dark Mode, "support both appearances"; Color).

**How the split works** (`HassDesign/SystemAppearance.swift`):
- The shell and the galleries keep `preferredColorScheme(.dark)` on the window, which hides the user's appearance from their own environment. `RootView` publishes the display's own interface style instead (`UIScreen`, which the override does not touch; `publishesSystemAppearance()`) as `EnvironmentValues.systemColorScheme`, and each sheet reads the display again when it is presented, so a change made while the app runs reaches the next sheet at once. The window scene's traits were observed dark while the display was light, so they are not the source.
- Known gaps: the system navigation subtitle ("Playing") is drawn by UIKit in `secondaryLabel` and measures 3.3:1 on a light sheet, as in Apple's own sheets, so the journey audit waives it as system chrome. The vacuum map canvas keeps its dark neutral ground in a light sheet.
- Every sheet states that scheme for itself: `hassSheet()`, `HassModal`, `FilterSheet`, `OptionPickerSheet` and the inventory editor apply `followsSystemAppearance()`. A sheet that bypasses all of those stays dark, so a new sheet must use `hassSheet()`.
- Always dark by design, passed as `hassSheet(appearance: .dark)` or `preferredColorScheme(.dark)`: the Weather sheet (a condition gradient), the camera viewer (live video), Login and the Location permission sheet.
- Tokens are light and dark pairs resolved from the scheme at draw time (`Color.adaptive`), so a view needs no branch: the same `Surface.sheetCell` is white in a light sheet and `#2C2C2E` in a dark one, and on a page (always dark) it never changes. Debug builds also honour `FENTON_APPEARANCE=light|dark` at launch, so journeys can render sheets in light without changing the simulator.

| Token | Dark | Light |
|---|---|---|
| `Surface.sheetGround` | `#1C1C1E` | `#F2F2F7` |
| `Surface.sheetCell` | `#2C2C2E` | `#FFFFFF` |
| `Surface.secondaryInSheet` | `#EBEBF5` at 60% | `#3C3C43` at 76% (the system's 60% is 3.3:1 on white; this is 5:1 or better on the ground and the cell) |
| `Surface.separator` | white at 14% | `#3C3C43` at 29% |
| `Ink.action` (text and glyph tint) | `#409CFF` | `#0066CC` |
| `Ink.error`, `Ink.danger`, `Ink.warning` | `#FF6961`, `#FF6961`, `#FFB340` | darker reds and amber at 4.5:1 or better on white |
| `Ink.success` | `#30D158` | `#1E7B34` |

**Tiles and rows in a light sheet:**
- An off tile is a white cell with label-colour title, `secondaryInSheet` state and the family glyph. Each family has a darker light glyph (`ColorFamily.glyphLightRGB`, at least 3:1 on white and on the ground, same hue); the off glyph mixes it 72% with `#6C6C70`.
- Error faces draw `#C21717` (6:1 on white). A state wash tints the cell at 22% instead of 60% so the secondary ink holds 4.5:1.
- Lit tiles and filled family tiles are unchanged: fixed fills with fixed inks look the same in both appearances, which is also what keeps the family colour meaning.
- A caller's tint on a family-less tile is darkened until it reaches 3:1 on the ground.
- `ModuleList` and `ModuleRow` in a sheet draw their cell, hairlines, title and secondary ink from the same tokens.
- The brightness bubble stays a dark capsule with white text in both appearances, like the system volume HUD.
- Selected rooms in the vacuum sheet are the label's opposite (white with dark ink in dark, `#1C1C1E` with white ink in light), because white would vanish on a white cell.

## Colour

- **Labels:** white; secondary `rgba(235,235,245,.68)` on material and `.6` in sheets; separators white at 14%.
- **Tint:** system blue.
  - Text and glyph actions on dark: `#409CFF`.
  - Filled controls with white text: `#0071E3`.
  - Neither `#007AFF` nor `#0A84FF` passes contrast as small text on dark.
- **Destructive, error and overdue:** `#FF6961`. Soon or warning: `#FFB340`. Count badges: `#D93025`.
- **Colour families** (owner request, 2026-10-14): every kind of device has one colour, used for glyphs, chips and filled tiles, never for chrome.
  - Off tiles stay dark, with the glyph in the family colour mixed 72% with grey.
  - On tiles fill with the family colour (a slight top highlight) and white ink, with subtitles at 92% white. Every fill passes 4.5:1 with white.
  - Lights keep the warm lit tile. Power uses bright yellow with dark ink.
  - Red is never a family: alerts are a red glyph and red state on any tile.
  - **Thermostats and bed sides keep a family when off** (owner, 2026-10-15; mockup fc-families): heating and cooling fill as above. An idle or off thermostat draws the off face with the Heating glyph when its HVAC mode is `heat`, else the Cooling glyph. A bed side that is on fills whatever its level (owner, 2026-10-16: "Beds are on right now but still no colors"): Heating at or above zero, Cooling below; an off side draws the off face with that family's glyph. Bed cards read the side's level and power through `BedSideController`, never the climate entity, whose state says `heat` whatever the pod does. Never grey, except an unavailable bed side. One rule: `HassDesign/ThermostatTileFace`.

| Family | Members | Glyph on dark | On-tile fill |
|---|---|---|---|
| Lights | lights, lamps, wake lights | `#FF9630` (web chip icon) | lit tile `#FFF3DE` → `#FFE2B2` over `#EADBC4`, glyph `#D97A00`, dark ink |
| Heating | thermostats and bed sides while heating | `#FF7A2F` | `#A8440A` (dial heat `#CD5401` darkened for white text) |
| Cooling | thermostats and bed sides while cooling | `#3FC6D2` | `#1B6F78` (dial cool `#2C8E98` darkened) |
| Vents | smart vents | `#8FA8FF` | `#3B58B8` |
| Air | fans, purifiers, bath fans, air quality | `#2FD3C1` | `#006E62` (web air teal) |
| Water | humidifiers, sprinklers | `#4CC9F0` | `#076C91` |
| Occupancy | presence and motion sensors | `#5BD16A` | `#2A732E` (web presence green) |
| Doors and windows | contact sensors, garage | `#7ED787` | `#3B523E`, the web's soft green |
| Media | TVs, remotes, consoles, PCs, speakers | `#FF7AA8` | `#A03A61` (web media pink) |
| Cleaning | vacuums, dishwasher, laundry | `#C88CFA` | `#7A3FB0`; progress is a lighter band from the leading edge |
| Power | plugs, towel rack, chargers | `#FFD60A` | `#FFE45C` → `#FFD60A`, dark ink |
| Cooking | grill, oven | `#FF8A4C` | `#A8420E` |
| Food (owner, 2026-10-16: "Food Spaces / All Food should have colours like the web") | Food hub tiles, always filled: Pantry `#855A25`, Fridge and All Recipes `#196B94`, Freezer `#2F4A9E`, Spice Rack `#AA4727`, Cabinet `#6A5F55`, All Food `#4A6B4E` | each a lightened tint of its fill | the web's tile colours (`ha-sfenton-react-dash@9ac2a46:src/constants/everShelfFood.ts:13-18`, `FoodHubPage.tsx:46,60`), nudged until white ink passes 4.5:1 and no two spaces read as one (≥ 30 apart in sRGB). The Freezer indigo sits near Vents and the Spice Rack near Cooking, as the web's own colours do; they never share a page |
| Security | by mode, as on the web | white on the fill | Home `#1565C0`, Away `#C62828`, Night `#7B1FA2`, Disarmed `#2A732E`, Triggered `#D70015` |

**Status chips follow the web** (owner, 2026-10-16: climate, air quality, occupancy and contact chips brought to web parity; one rule per chip, in `StatusChipAppearance` and `HassCore/Chips`):
- Lights on: amber, orange glyph.
- Security: filled with the mode colour, white glyph.
- **Climate follows the temperature** (owner, 2026-10-16: "temperature-dependent, like the web"). The web colours every climate card with the `input_text.*_climate_color` helper Home Assistant computes, else its temperature gradient (`ha-sfenton-react-dash@9ac2a46:src/components/cards/climateColor.ts:8-15,49-59`, `ClimateCard.tsx:71`). The Home chip reads `input_text.all_climate_color`, a room chip its `input_text.<room>_climate_color`; with neither it takes the gradient at the mean of the range text (50 °F blue, 60 purple, 68 green, 74 yellow, 80 orange, 85 red, clamped). The fill is that colour scaled to 73% (and darkened further until white reads at 4.5:1, also under the top highlight); the thermometer stays the web's yellow `#FFCC00` where it keeps 3:1, else a lightened tint. No colour at all falls back to the old navy `#195482`. Beds keep the family colour.
- **Air quality follows the AQI.** Fill and glyph use `input_text.all_aqi_color` (a room chip its `input_text.<room>_aqi_color`; the web teal `rgb(0, 150, 136)` while unset) through the same scale-and-lighten rule, so good air is `#006E63`, within a step of the Air family teal. The summary is the web's, `AQI <range> · PM2.5 <range>` (`AtAGlancePage.tsx:1187`); the web has no "Good" word on this chip, so there is none.
- **Occupancy:** a person glyph, outline while clear and filled while detected, with the Occupancy green fill only while detected. The web tints this chip by detection alone (`StatusRail.tsx:41-46`: green fill and `motion-sensor` when active, neutral `motion-sensor-off` when clear); it has no alarm or away tint, so neither has the native chip.
- **Contact Sensors reads the house** (owner, 2026-10-16: "need to decide all closed, open but we're home, open but we're away, open but security system is on"). The web draws this chip green when open and neutral when closed and has no house rule, so these are the planner's decisions. One rule, `ContactChipState`, shared by Home, every room rail and Security:

| State | When | Fill | Glyph | State text |
|---|---|---|---|---|
| All closed | nothing open | soft contact green `#3B523E` | door closed, `#7ED787` | "All Closed" (a single sensor: "Closed") |
| Open, home | something open, someone home, system not armed | warning amber `#8A5200` (the `#FFB340` warning, darkened for white text) | door open, `#FFC25C` | "<n> Open" |
| Open, away | something open, household effectively away, system not armed | the web's window-open coral `#B23A26` | door open, `#FFD2C8` | "<n> Open" |
| Open, armed | something open and the alarm is in any armed mode or triggered (outranks away) | triggered red `#D70015` | alert triangle, white | "<n> Open" |

  "Away" is `ClimateLogic.isEffectivelyAway` (Whole Home mode, `sensor.thermostat_effective_home_away`), the app's one home/away reading. The alert triangle keeps the armed state from resting on colour alone. The web's count text ("N Open") stays; the owner's "Back Deck Open" wording was an example, and the web has no per-sensor name here.
- **Colour changes animate.** A chip's fill and glyph cross-fade when the colour changes or the chip turns on or off (a warmer house, a door opening, the alarm arming): 0.6 s ease-in-out, scoped to colour so the chip's width and glyph never slide. Reduce Motion allows the cross-fade (no movement), shortened to 0.2 s (`StatusChipStyle.colorAnimation`).

**Security Doors are tiles** (owner, 2026-10-16): the Doors section is a grid of `GlassTile`s in the Doors and windows family (front-door lock, left and right garage doors; Mach-E's car lock when shown), not rows. A tile is filled while the door is open, unlocked or moving and dark while closed or locked; a jammed lock or a failed garage command draws the red error face; garage doors keep their Sending, Opening, Closing and Error states. Same grid rules as room tiles: 140 pt scaled minimum width, equal heights, one column at accessibility sizes.

People and rooms have no colour of their own.

## Type

SF Pro only.
- **Large titles:** 34 Bold.
- **Section headers:** 20 Bold on pages and over tile grids in sheets. Over inset lists in sheets, 15 Semibold secondary.
- **Rows:** 17 Regular. Subtitles 15, footers 13, tab labels 10.
- **Display numerals:** one per screen, Light or Thin weight, with monospaced digits. Examples: the thermostat (71 °F), weather (54°), a light's brightness, the humidifier mist level, the bed level.
- **Copy:** Title Case labels, states said as facts ("Back Deck Open", "Heating to 68°", "3 of 12 on"), dates as "Oct 16, 2026". No exclamation marks, no "currently", and no Home Assistant jargon.

## Navigation

- **iPhone and Duo folded:** a floating glass tab bar with Home, Security, Climate and Chores. Chores carries the overdue badge. Quick Links is a separate glass circle that trails the tab bar, and it presents the Quick Links sheet. Profile is a 44pt avatar circle top-trailing on tab roots; it opens the Account sheet, which holds People at Home, Your Summary, Settings with all sub-pages pushed inside it, and Sign Out.
- **Pushed pages** (Food, Media, Sprinklers, Custom Lights, room pages, chore lists): a glass Back circle with its top edge at y=54, left 16, and the large title with padding-top 104. The tab bar stays unless the page has its own bottom toolbar (Recipes and inventory use search, sort and filter).
- **iPad:** an overlay glass flyout (Open Navigation button top-leading) that lists the four tabs and then Quick Links. Grids reach at least 4 columns in portrait and keep growing (4 is a floor, not a cap), chips wrap, and Quick Links is a floating 56 pt glass circle bottom trailing.
- **Duo unfolded:** each half is its own column and nothing straddles the hinge. Column counts are even. The tab bar is centred in the left half, and the chip row stops 24pt short of the hinge.
- **macOS:** a sidebar with the four tabs, Quick Links in the toolbar, Settings in the app menu and a Settings window (⌘,). Every toolbar item is also a menu command. Sheets get a Close button in the content area, and the thermostat and remote open as panels.

## Sheets

- Full height on iPhone. Form or page sheets on iPad. Medium detents only for short prompts (the bed's Tonight / All Nights choice, Lighting Mode, rename, Add Grocery).
- **Viewing and control sheets:** circle x Close trailing. Leading is empty at the root, or a glass Back circle on pushed levels (Lights → Kitchen Lights → Table Light). Centred title plus a one-line subtitle. Never "Done".
- **Create and edit sheets:** circle x Cancel leading and a filled `#0071E3` checkmark trailing, as in Calendar and Reminders. Reset is a list row. Multi-step flows put Back leading on later steps.
- **Sections:** a bottom glass segmented control, never a top one. Use symbols and labels, or symbols only at five segments (the vacuum). The control only shows sections that have content (the remote has 2 to 4). Content cross-fades with no layout jump.
- **Alerts:** iOS 26 style for destructive or hard-to-undo actions: Disarm, Turn Off Vacation Mode, Sign Out. The destructive button is red.

## Controls

| Control | Rule |
|---|---|
| Status chips (Home, room pages, Security) | Capsules with glyph, title and one-line state, coloured as on the web (see Colour families, "Status chips follow the web"); Contact Sensors also read the house. Neutral when nothing is active. Colour changes cross-fade. They scroll horizontally in compact width and wrap in regular width (`ChipRail`). |
| Tiles | 2 columns on iPhone, 22pt radius, equal heights within a grid (the tallest name, such as "Master Bedroom Closet" on two lines, sets the row). Off is dark with the glyph in its family colour. On fills with the family colour and white ink; lights use the warm lit tile. Errors use a red glyph and red state text. A chevron appears only when the tile opens something. |
| **Light dragger** (signature) | Tap a light tile to toggle it. Press and drag sideways to set brightness: the bright band follows the finger, a "30%" bubble floats beside it, there is a haptic tick every 10%, and the tile lifts while dragging. A room's lights stack as full-width slabs that work the same way. The light detail adds a 168pt brightness slab, White and Color modes, a colour-temperature track with presets, and a colour wheel. |
| **Thermostat dial** (signature) | main's `ThermostatDial` exactly: a 22pt round-capped 270° track, heat arc orange to the heat setpoint, cool arc teal from the cool setpoint, white knobs, a dark dot for the current temperature, "Heating", a Thin numeral with a raised °F, and the range line. The bed and humidifier dials reuse its geometry. |
| **Remote** (signature) | A 3×3 grid of 72pt grey circles: Back, Up, Power (red glyph, top-trailing), Left, OK, Right, Home, Down, Menu. Volume is a slider with speaker − and +. Transport keys sit below. |
| Choosing one option | Alarm modes are mode tiles. 2–4 short options use the system segmented control. Options with descriptions use a checkmark list. Longer short lists use a pop-up menu (`Picker(.menu)`) that stays anchored over the control, for example suction, passes and repeat. Thermostat Hub mode and Fan are pop-up menus too, because Stephen asked for a native dropdown there. |
| Switches | Only in list rows. |
| Primary buttons | At most one per screen: a 50pt capsule filled `#0071E3` with a white label. A sheet about one owner's thing may use that owner's hue with dark text (Sprinklers cyan). There are no white or grey primary buttons. |
| Lists | Inset grouped, 26pt radius on pages, 52/60pt rows, hairlines inset to the text. Footers carry the web's explanations; on the wallpaper, explanations go inside the card. |
| Cameras | 2×2 on Home and Security, cards 1 : 0.78 like the web's tile (fill-cropped, centred), nothing over the image except a small name label with a red live dot while the stream shows frames (HIG HomeKit must). The viewer is full-bleed with a live dot and glass Snapshot / Audio / Record. While connecting, or after a live stream stalls, the last snapshot stays fully visible with a pill: "Last live 6:51 PM" once the stream has been live (the snapshot's own time is not known), else "Connecting". |
| Vacuum map | Flat neutral room shapes. Selected rooms are white with black numbered order badges, and skipped rooms are hatched. While cleaning, the map grows and the controls collapse to one card with Pause and Stop. |

## Loading and feedback

- With a saved snapshot, Home shows it at once with a small "Updating" glass pill by Profile.
- With nothing saved, show one centred arc spinner on the wallpaper, with no empty cards, and then everything fades in together. Images are shown from the on-disk cache first.
- **Spinners are the web's arc** (`DashboardPageLoading`), not the system petal indicator. The arc is a ring at 22% opacity with the top quarter at 96% and the right quarter at 72%. It turns once every 820 ms, linear, and takes the colour of the text around it. Sizes: 44pt with a 3pt ring for pages, 20pt for pills and rows, 16pt inline in buttons and subtitles. It is spoken as "Loading", or as the action it stands for, such as "Sending Open". With Reduce Motion on, it keeps turning at half speed, because a still arc reads as frozen. (Owner request, 2026-10-14.)
- Optimistic taps change the tile at once. If Home Assistant doesn't confirm, the tile reverts and shows "Didn't respond" in red. Garage doors show Sending, Opening, Closing and Error states on their buttons.

## Open questions waiting on Stephen (defaults shown in the mockups)

- **Occupancy:** a "Who's Home" list is added.
- **Doors chip:** it names a real sensor.
- **Chore lists:** shown neutral grey; the alternative is their web colours.
- **Donetick labels:** not on the task form.
- **Settings:** lives inside the Account sheet. Vacation and To-Do appear in both Quick Links and Settings.
- **Duo:** four chips show beside the hinge.
- **Advanced Controls root:** has no Back button.
- **Garage:** opens on tap, with no confirmation.
- **Mach-E:** its Doors tile is shown on Security.
- **Room pages:** keep the Lights chip; the alternative is a tile per light.
- **Remote apps:** placeholder icons, not real app icons.
- **Library:** kept as a storage choice.
- **Swipe actions:** used for row Edit and Delete.
