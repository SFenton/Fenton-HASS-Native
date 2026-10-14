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
| Wallpaper | The house photo (`/local/images/house.webp`), blurred 20, saturation 1.1, scaled 1.06, under a dark scrim. The scrim runs 0.36 → 0.18 (28%) → 0.36 (50%) → 0.50 → 0.64 from top to bottom. Decode it once at screen size, blur it once and cache the bitmap; never run a live `.blur` per frame. | Every tab root and pushed page, on every platform. Never in sheets. |
| Modules on the wallpaper | `systemGray6` dark at 55% with a 30pt background blur (thin material), 26pt radius, no rim or bevel, white text. A module that carries red or orange status text (overdue chores, expired food, an error tile) uses the denser `rgba(20,20,22,.78)` so that text stays readable over the lit windows. | Cards, inset lists and tiles on pages. These are content-layer materials and never `.glassEffect` (HIG must). |
| Sheets | System sheet in dark appearance: `#1C1C1E` ground, `#2C2C2E` cells and tiles. The presenting page scales back and dims. | Every modal. |
| Liquid Glass | System glass. iOS 17–25 fall back to `.ultraThinMaterial` capsules. | Navigation only: the tab bar, the Quick Links circle, toolbar circles (Profile, Back, Close, Cancel, Save), bottom section controls and page bottom toolbars. |

Pages are always dark-styled because they sit on the dimmed photo, the way Apple Home's wallpaper works. Sheets are designed dark in the mockups. Light appearance for sheets is a follow-up.

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
| Security | by mode, as on the web | white on the fill | Home `#1565C0`, Away `#C62828`, Night `#7B1FA2`, Disarmed `#2A732E`, Triggered `#D70015` |

**Status chips follow the web:**
- Lights on: amber, orange glyph.
- Security: filled with the mode colour, white glyph.
- Climate: always web navy `#195482` with the yellow `#FFCC00` thermometer.
- Occupancy: green fill with a white walking glyph when occupied, neutral when clear.
- Doors or windows open: soft green with a green door-open glyph, neutral "All Closed" when shut.
- Air quality: teal fill, glyph in the AQI colour.

Open doors and occupancy are both green on the web. The softer fill tells them apart. The alternative, if they should differ, is the web's window-open coral (`#B23A26` fill).

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
- **iPad:** an overlay glass flyout (Open Navigation button top-leading) that lists the four tabs and then Quick Links. Grids use 4 columns, chips wrap, and Quick Links is a floating button.
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
| Status chips (Home, room pages, Security) | Capsules with glyph, title and one-line state, coloured as on the web (see Colour families). Neutral when nothing is active. They scroll horizontally. |
| Tiles | 2 columns on iPhone, 22pt radius, equal heights within a grid (the tallest name, such as "Master Bedroom Closet" on two lines, sets the row). Off is dark with the glyph in its family colour. On fills with the family colour and white ink; lights use the warm lit tile. Errors use a red glyph and red state text. A chevron appears only when the tile opens something. |
| **Light dragger** (signature) | Tap a light tile to toggle it. Press and drag sideways to set brightness: the bright band follows the finger, a "30%" bubble floats beside it, there is a haptic tick every 10%, and the tile lifts while dragging. A room's lights stack as full-width slabs that work the same way. The light detail adds a 168pt brightness slab, White and Color modes, a colour-temperature track with presets, and a colour wheel. |
| **Thermostat dial** (signature) | main's `ThermostatDial` exactly: a 22pt round-capped 270° track, heat arc orange to the heat setpoint, cool arc teal from the cool setpoint, white knobs, a dark dot for the current temperature, "Heating", a Thin numeral with a raised °F, and the range line. The bed and humidifier dials reuse its geometry. |
| **Remote** (signature) | A 3×3 grid of 72pt grey circles: Back, Up, Power (red glyph, top-trailing), Left, OK, Right, Home, Down, Menu. Volume is a slider with speaker − and +. Transport keys sit below. |
| Choosing one option | Alarm modes are mode tiles. 2–4 short options use the system segmented control. Options with descriptions use a checkmark list. Longer short lists use a pop-up menu (`Picker(.menu)`) that stays anchored over the control, for example suction, passes and repeat. Thermostat Hub mode and Fan are pop-up menus too, because Stephen asked for a native dropdown there. |
| Switches | Only in list rows. |
| Primary buttons | At most one per screen: a 50pt capsule filled `#0071E3` with a white label. A sheet about one owner's thing may use that owner's hue with dark text (Sprinklers cyan). There are no white or grey primary buttons. |
| Lists | Inset grouped, 26pt radius on pages, 52/60pt rows, hairlines inset to the text. Footers carry the web's explanations; on the wallpaper, explanations go inside the card. |
| Cameras | 2×2 on Home, nothing over the image except a small name label (HIG HomeKit must). The viewer is full-bleed with a live dot and glass Snapshot / Audio / Record. While connecting, the last snapshot stays fully visible with a "Snapshot from 6:51 PM" pill. |
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
- **Mach-E:** its Doors row is shown on Security.
- **Room pages:** keep the Lights chip; the alternative is a tile per light.
- **Remote apps:** placeholder icons, not real app icons.
- **Library:** kept as a storage choice.
- **Swipe actions:** used for row Edit and Delete.
