# Telemetry

> **What:** how the app measures its own performance. **Read when:** adding a page, a scroll view, a loader or anything that could cost frames.

- **Module:** `HassTelemetry` (`Telemetry`, `TelemetryLog`). It has no dependencies; every other module may use it.
  - **Signposts** (`OSSignposter`, subsystem `com.sfenton.home`, category `Performance`) are always on. Instruments and `XCTOSSignpostMetric` read them.
  - **In-app log**: a 4000-sample ring with counters and per-page scroll stats. It records while `Telemetry.isEnabled`: Debug builds, `FENTON_TELEMETRY=1`, or the switch on the Performance screen.
- **Names** (`Telemetry.Name`; tests depend on them): `EntityUpdate`, `ContentReady`, `ImageFetch`, `ImageDecode`, `ServiceCall`, `OptimisticConfirm`, `Scroll` and `Hitch`. `SnapshotSave` measures the debounced snapshot write.
- **Scrolling:**
  - Every page's main `ScrollView` / `List` carries `.scrollTelemetry("<Page>")` (`HassUI/Diagnostics/FrameMonitor.swift`).
  - While it scrolls, a 120 Hz display link times each frame. A frame later than half a budget counts as a hitch, and the page's hitch ratio (ms per s) is recorded.
  - A new page must add the modifier; it is one line.
  - `CADisableMinimumFrameDurationOnPhone` is set, so ProMotion iPhones scroll at 120 Hz.
- **MetricKit:** `MetricKitCollector` keeps daily metric and diagnostic payloads (scroll hitch ratio, hangs) under `Caches/MetricKit`. It only runs on physical devices.
- **Seeing it:**
  - Settings → Performance (`PerformanceScreen`) shows scrolling per page, page loading, live updates, actions and images.
  - **Export Telemetry** shares one JSON file containing the log plus the MetricKit payloads.
  - Gallery: `FENTON_GALLERY=performance` (seeded).
- **Privacy:** nothing leaves the device unless the user exports it. Records carry page names and entity ids, never values or credentials.
