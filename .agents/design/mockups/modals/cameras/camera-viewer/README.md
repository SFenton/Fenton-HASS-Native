# Camera viewer (modal)
> **What:** The camera's shared live stream with Snapshot, Sound and Record under it, always dark; fitted detent in flight. **Read when:** you change `CameraViewer`, `CameraLiveView` or the stream pool.
- Mockup: [camera-viewer.html](camera-viewer.html) · status in-flight:fix/camera-viewer-fitted (uncommitted in the primary checkout; main opens at large) · reviewed 2026-10-23
- Source: `HassUI/Features/Cameras/CameraViewer.swift`, `CameraLiveView.swift`, `CameraLiveModel.swift`, `CameraStreamPool.swift`, `HassDesign/SheetFit.swift` · Spec: `.agents/patterns/camera-streams.md`, `.agents/design/mockups/proposals/camera-viewer-fit/camera-viewer-fit.html` · Patterns: camera-streams, modal-sheet
- States covered: default (live), loading (connecting), error (failed + Retry), offline (stalled), live-delayed, stalled, recording, sound-on, snapshot saving/saved/failed, four cameras, was-full (main), medium, large, fitted, closed, ax5
- Motion: phase fade (quick), snapshot save, record pulse, sheet fit; transitions: present, dismiss, Photos alert
- Devices: iPhone, Duo folded, Duo unfolded landscape, iPad portrait and landscape (split in landscape)
- Open notes: docs call it full-screen or large; code is a dark page sheet; copy on the Photos alert says "Home"; shared helpers in `components/media/_media-lights-cameras.js` (promote to kit)
