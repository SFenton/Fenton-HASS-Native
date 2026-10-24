# Grill (Bear Grills) sheet (modal)
> **What:** the Back Deck grill sheet: state header, probe and pellet readings, Keep Warm and Super Smoke switches. **Read when:** you change `GrillSheet` (it lives in AirPurifierSheet.swift).
- Mockup: [grill-sheet.html](grill-sheet.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/RoomDevices/AirPurifierSheet.swift, RoomDeviceSheetChrome.swift, HassCore/RoomDevices/AirPurifierController.swift` (paths under `apple/Sources/` unless full) · Spec: `.agents/patterns/room-device-sheets.md` · Patterns: room-device-sheets, modal-sheet, entity-tile
- States covered: cooking, keep warm, off, unavailable, offline, medium, large, fitted, closed, ax5
- Motion: switch tile colour, header circle colour (0.6 s); transitions: present, dismiss
- Devices: iPhone, Duo folded, Duo unfolded landscape, iPad portrait and landscape (form sheet)
- Open notes: sensor cards never fill (isActive is false for numbers); state vocabulary comes from the Traeger integration
