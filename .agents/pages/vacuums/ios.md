# Vacuums: iPhone and iPad

> **What:** native Vacuums implementation notes. **Read when:** changing `HassUI/Features/Vacuums` or `HassCore/Vacuums`.

- `VacuumsScreen` reads the environment `HassConnection`; `VacuumsPage` takes a store and caller so the gallery and hosted tests drive it with fixtures. Two sections, Robot Vacuums and Auto-Clean, on `DynamicGridLayout`. Where `SplitPolicy.allowsSplit` (unfolded Duo landscape, iPad landscape) they sit side by side, each scrolling on its own; everywhere else they stack. HIG: Layout, Split views.
- Auto-Clean tiles are switches (`VacuumAutoCleanController`): the Main Floor pause switch is inverted (enabled when off). Optimistic, cleared on confirmation, reverted after 8 s.
- Tapping a robot opens `VacuumSheet` (`.vacuumPresentation()`, large detent, page sizing on iPad); see [vacuum-sheet](../../patterns/vacuum-sheet.md). Home links to the page from the Cameras row (`home.vacuums`) until side navigation lands.
- The map is the Valetudo map camera's `entity_picture` PNG with the map JSON in its `zTXt` chunk; see [valetudo-map](../../patterns/valetudo-map.md). It polls every 3.5 s while the robot is live; an unavailable robot shows its last reported map without paths.
- Services come from `get_services` once per sheet, so scripts the server lacks (area clean, dock) disable their buttons instead of failing.
- Debug gallery: `FENTON_GALLERY=vacuums` with `FENTON_GALLERY_VACUUM=<map id>`, `FENTON_GALLERY_TAB=controls|zones|autoClean|more|info` and `FENTON_GALLERY_SCENARIO=docked|cleaning|error|resumable|unavailable`. Fixture maps and a recording caller; nothing reaches a real robot. Journeys: `VacuumJourneyTests`.
