# Climate (page)
> **What:** the Climate tab: the Whole Home thermostat dial on the wallpaper, the Thermostat Hub pill, notices, open contact sensors and the three Advanced Controls rows. **Read when:** you change `ClimatePage`, the dial's page use, the hub pill or the notices, or need the page's states on every device.
- Mockup: [climate.html](climate.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/Climate/ClimateScreen.swift`, `ClimateComponents.swift`, `HassUI/Controls/Thermostat/ClimateThermostatDial.swift`, `HassDesign/ThermostatDial/*`, `HassCore/Climate/ClimateLogic.swift`, `HassCore/Config/ClimateConfig.swift`
- Spec: `.agents/pages/climate/spec.md`, `ios.md`, `.agents/patterns/thermostat-dial.md` · Patterns: thermostat-dial, module-list, dynamic-grid, modal-sheet, motion
- States covered: default (heating, a window open), loading, refreshing, empty (nothing open), error, offline, reconnecting (arc, plus the orange chip it replaces), long-text, cooling, idle, off, away (eco thermostat, notice, warning), integration-off, hub-menu, ax5
- Motion: dial handles glide (quick 0.2 s), status colour on the dial and hub glyph (state 0.6 s), warning notice. Transitions: Advanced Controls sheet, tab cut, hub pop-up menu
- Devices: iPhone, Duo folded, Duo unfolded landscape and portrait, iPad portrait and landscape; always one 720 pt column (never splits)
- Open notes: numerals do not roll in the code (docs say they do); arcs step while handles glide (RingArc has no animatableData; confirm on a device); the kit's `.k-wrap h2` leaks into `.ui-hdr h2` (worked around in the shared helper)
