# Mockup kit

> **What:** the shared kit behind every mockup in the atlas: tokens, device chrome, motion helpers and one builder per shared SwiftUI component. **Read when:** you need a component, a token or a helper before you write a mockup. The contract is [AUTHORING.md](AUTHORING.md); `gallery.html` renders everything below.

Call a component as `Mock.components.<Name>(props)` (returns a DOM node) or `var K = Mock.components`. Screens: `Mock.page(ctx, opts)`, `Mock.sheet(ctx, opts)`, `Mock.split(ctx, {leading, trailing})`, `Mock.frame(ctx, node)`. Component mockups: `Mock.componentConfig('GlassTile')`. Paths are under `apple/Sources/`. Variants are in each file's `.variants` and `.states`.

| Component (`Mock.components.`) | SwiftUI source | Props (see the file header) | Variants and states |
|---|---|---|---|
| `GlassTile` (= `GlassTileFace`) | HassDesign/GlassTile.swift | `title subtitle symbol family fill room quickLink tint isActive isUnavailable isError kind wash progress layout titleLines accessory pending` | every family on, rooms, Quick Link, stacked; off lit error pending unavailable progress tinted navigate |
| `TileGrid` (= `DynamicGrid`) | HassDesign/DynamicGridLayout.swift | `items (props or nodes) min max gap equal span` | min 150 / max 2 / wide; even columns on a hinge |
| `ChipRail` | HassDesign/ChipRail.swift | `chips ctx frame mode` | scroll, wrap, hinge gap |
| `StatusChip` + `Mock.chips.*` | HassUI/Features/Home/StatusRail.swift | `title summary symbol family isActive tint dim pending` | lights, 5 security modes, climate gradient 50..85, AQI, occupancy, 4 contact states |
| `ModuleList`, `ModuleRow`, `ToggleRow` | HassDesign/ModuleList.swift | `rows density hasGlyphs` / `title subtitle symbol glyph chevron accessory` | thin, dense, no glyphs |
| `SettingsSection`, `InlineAlert`, `SelectableOptionRow` | HassDesign/SettingsSection.swift | `title paragraphs content` / `message severity` / `icon label description selected` | warning, error |
| `PageSectionHeader` (= `RoomSectionHeader`) | HassDesign/PageSectionHeader.swift | `title detail` | plain, detail |
| `HassModal` | HassDesign/HassModal.swift | `title subtitle leading trailing confirm content tabs fitted` | viewing, edit, pushed (use `Mock.sheet` for the detent panel) |
| `SheetCloseItem`, `SheetCancelItem`, `SheetConfirmItem` | HassDesign/HassModal.swift, SheetEditToolbar.swift | `title enabled busy` | enabled, disabled, busy |
| `FloatingActionBar` | HassDesign/FloatingActionBar.swift | `actions search ctx` | primary, secondary, search+sort+filter; reflows at AX |
| `FilterSheet`, `FilterSection`, `FilterOptionRow` | HassDesign/FilterSheet.swift | `sections canReset` | default, changed |
| `OptionPickerSheet` | HassDesign/OptionPickerSheet.swift | `options selected` | labels, swatches |
| `StatusPill`, `InfoBox` | HassDesign/StatusPill.swift, InfoBox.swift | `label value detail symbol tone` / `title message tone` | six tones; success, neutral |
| `PrimaryButton`, `SegmentedChoice`, `Toggle`, `Slider`, `SliderRow` | HassDesign/PrimaryButton.swift, HassUI/Common/SegmentedChoice.swift | `title symbol family` / `options selected style` | default, family hue, disabled; menu at AX |
| `BrightnessTile` | HassDesign/BrightnessTile.swift | `title percent dragging tint unavailable` | 70, 30, coloured bulb; off, drag, unavailable |
| `ThermostatDial` | HassDesign/ThermostatDial/ThermostatDial.swift | `value heat cool mode range size` | heating, heat+cool, cooling |
| `ArcSpinner`, `ArcProgress` | HassDesign/ArcSpinner.swift | `size label color` / `label fraction` | page 44, compact 20, inline 16 |
| `ContentGate`, `Skeleton`, `PendingValueBar` | HassDesign/Loading/ContentGate.swift | `content phase label` | loading, spinner, ready (`Mock.anim.gate` plays it) |
| `CameraTile`, `ImageCard` | HassUI/Features/Home/CameraGrid.swift, HassDesign/ImageCard.swift | `title state since scene` / `title subtitle scene` | live, snapshot, connecting; recipe |
| `ModalTabBar` | HassUI/Common/ModalTabBar.swift | `tabs selected ctx` | icons, titles, badges, menu at AX |
| `QuickLinksButton`, `ProfileButton`, `HamburgerButton`, `BackButton`, `CloseButton`, `RailGroup`, `NavigationGlass` | HassUI/App/Shell/ShellHeader.swift | `name badge offline` | monogram, badge 3, 9+, no name, offline cloud |
| `TabBar`, `NavigationFlyout` | HassUI/App/MainTabView.swift, Shell/NavigationFlyout.swift | `selected badges orientation` | five tabs, Chores badge, vertical rail |
| `ReconnectingArc`, `OfflineChip` | HassUI/App/Shell/ReconnectingArc.swift (in flight), ReconnectingChip.swift | `on` / `variant` | visible, hidden; offline, was (orange chip) |
| `ScheduleDateFields`, `FormField`, `FormSection` | HassDesign/ScheduleDateFields.swift, FormSectionText.swift | `fields` / `label value kind on` / `header footer fields` | text, value, toggle, stepper |
| `Alert` | HassUI/Features/Security/SecuritySystemSheet.swift | `title message buttons` | destructive + cancel |
| `AlarmPanel`, `AlarmModeButton` | HassUI/Features/Security/SecuritySystemSheet.swift | `state since surface` | five modes, arming, unavailable |
| `WeatherCard`, `WeatherCardHeader`, `WeatherGlyph` | HassUI/Features/Home/Weather/ | `condition temp hi lo glyph pending` | short, long (ticker), unavailable, pending, 7 glyphs |

## Helpers worth knowing

- `Mock.icon(name, {fill, size, label})`: SF Symbol look-alike as an SVG string; `Mock.iconEl` returns a node. 140 names (`Mock.iconNames()`).
- `Mock.chips.home(opts)`, `.lights`, `.security`, `.climate`, `.contacts`, `.airQuality`, `.occupancy`, `.unavailable`: StatusChip props with the app's colour rules; `Mock.chips.fromWeb(rgb)` is ChipTint.fromWeb.
- `Mock.anim.*`: `fade rise stateColor toggleState roll ticker stagger arrival arc sheet push zoom cut flyout gate spinner series` (each cites motion.md).
- `Mock.scene(name)`: stand-in photo backgrounds (`front-door driveway upper-deck lower-deck recipe`). `Mock.tabs`: the five sections. `Mock.securityModes`.
- `Mock.lint(cfg)`: the problems the red banner lists. `Mock.devices`, `Mock.ctx(key, {appearance, ts, reduceMotion, reduceTransparency})`, `Mock.current`.
- CSS: tokens only through `var(--...)`: `--fam-<family>-glyph|fill`, `--room-*`, `--ql-*`, `--sheet-ground|cell`, `--ink`, `--ink-sheet-2`, `--sep`, `--ink-action`, `--g-module-thin|dense`, `--fs-*` (Dynamic Type), `--sc` (metric scale).
