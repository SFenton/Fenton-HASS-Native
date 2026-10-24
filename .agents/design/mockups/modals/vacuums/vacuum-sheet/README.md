# Vacuum sheet (Controls, Rooms, Auto-Clean, Dock, Info) (modal)
> **What:** the robot vacuum sheet: map, status, report row, and five sections in the bottom bar; map grows while cleaning. **Read when:** you change `VacuumSheet`, its tabs, the map panel or the status/command copy.
- Mockup: [vacuum-sheet.html](vacuum-sheet.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/Vacuums/VacuumSheet.swift, VacuumTabs.swift, VacuumMapPanel.swift, VacuumComponents.swift, HassCore/Vacuums/VacuumController.swift` (paths under `apple/Sources/` unless full) · Spec: `.agents/patterns/vacuum-sheet.md, valetudo-map.md, pages/vacuums/ios.md` · Patterns: vacuum-sheet, valetudo-map, modal-sheet, module-list
- States covered: docked (rooms, none, area), every section, Music and Theater robots, cleaning, dock prep, paused, error, resumable, low battery, unavailable (last map, no map), map loading, offline, clean failed, report notice, closed, ax5; medium/fitted do not exist
- Motion: tab swap fade (0.13/0.17 s), run-mode swap with map growth (0.28 s), room card colour, map selection; transitions: present, dismiss, tab, area editor, report, switch dialog
- Devices: iPhone, Duo folded, Duo unfolded landscape (two columns), iPad portrait, iPad landscape (two columns)
- Open notes: catalog says tab switch is a cut: code fades; SmoothContentSwap timings are not in motion.md; ModalTabBar always icons at compact width
