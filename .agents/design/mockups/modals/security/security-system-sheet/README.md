# Security System sheet (modal)
> **What:** the sheet the Security chip opens: one card with the alarm mode and the four mode buttons, fitted height, light and dark. **Read when:** you change `SecuritySystemSheet`, `AlarmPanel`, the Disarm alert, or need a reference for a sheet built with the kit.
- Mockup: [security-system-sheet.html](security-system-sheet.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/Security/SecuritySystemSheet.swift`, `HomeScreen.swift`, `HassDesign/HassModal.swift`, `SheetFit.swift`, `HassCore/Config/SecurityConfig.swift` · Spec: `.agents/pages/security/spec.md`, `ios.md` · Patterns: modal-sheet, header-edge-fade, motion
- States covered: default (armed home), loading (arming), error (unavailable), offline (over an offline Home), disarmed, armed away, armed night, triggered, disarm-confirm alert, medium, large, fitted, closed (the presenter), ax5; dark and light side by side in the States gallery
- Motion: mode fill and badge cross-fade (0.6 s), triggered wash. Transitions: present, dismiss, Disarm alert
- Devices: iPhone, Duo folded, Duo unfolded landscape, iPad portrait and landscape (page sheet, 704 pt)
- Open notes: no true loading state (reads the store); on the unfolded Duo the centred sheet crosses the hinge band (placement is the system's, check on a device)
