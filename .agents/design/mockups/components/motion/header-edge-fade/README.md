# HeaderEdgeFade (component)
> **What:** content fades to clear under a page or modal header over a 40 pt ramp; hard edge for Reduce Transparency, Increase Contrast and iOS 17. **Read when:** you touch a header, a scroll-edge effect or a pinned bar.
- Mockup: [header-edge-fade.html](header-edge-fade.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassDesign/HeaderEdgeFade.swift`, `apple/Sources/HassDesign/NavigationGlass.swift` · Spec: .agents/patterns/header-edge-fade.md, .agents/design/direction-g.md · Patterns: header-edge-fade, modal-sheet, page-backdrop
- States covered: rule at three offsets, live scroll (page and sheet), sheet header, hard edge, real page, geometry, ax5
- Motion: fade follows the scroll offset (not time); hard edge switch
- Devices: iPhone and iPad size classes
- Open notes: doc says onScrollGeometryChange; iOS uses a UIKit observer
