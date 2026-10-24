# Home (page)
> **What:** the At a Glance overview as the app draws it today: status chips, weather, guests, cameras. **Read when:** you change Home, the status rail, the weather card, or the camera grid, or need a reference for a page built with the kit.
- Mockup: [home.html](home.html) · status shipped (weather header option D and the reconnecting arc are in-flight, marked) · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/Home/HomeScreen.swift`, `StatusRail.swift`, `CameraGrid.swift`, `GuestPresenceSection.swift`, `HomeColumns.swift`, `Weather/` · Spec: `.agents/pages/home/spec.md`, `ios.md` · Patterns: status-rail, dynamic-grid, page-backdrop, header-edge-fade, entity-tile, content-gate, motion
- States covered: default, loading (first sign-in, pulsing bars), refreshing (identical by design), error (entities unavailable), offline, reconnecting (arc, in flight), reconnecting-was (orange chip, main), long-text (ticker), weather-was (header on main), guests, ax5
- Motion: chip colour fade, chip off, weather number roll, weather ticker, reconnecting arc fade, sign-in arrival, pending pulse. Transitions: Security sheet, camera viewer sheet, tab cut, flyout
- Devices: iPhone, Duo folded, Duo unfolded landscape (two columns on the hinge) and portrait, iPad portrait and landscape (one column)
- Weather card: drawn by `components/weather/_home-weather.js` (page indicator, Previous and Next, "--" while loading), not the kit WeatherCard
- Open notes: no empty state (a note says why); direction-g first-sign-in spinner vs motion.md placeholders disagree (motion.md shown); unfolded Duo portrait not run on a simulator; wallpaper, cameras and weather glyphs are stand-ins
