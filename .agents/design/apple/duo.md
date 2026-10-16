# iPhone Duo

> **What:** foldable iPhone adaptation. **Read when:** changing layout that a fold or hinge can cross.

- Rotates freely folded and unfolded (`FentonOrientationSupport` allows all orientations once `HingePresence` sees a hinge or vertical bar). Folded and unfolded portrait are single page; unfolded landscape may split ([split-view](split-view.md)).
- Carry over FestivalNativeApps' Duo rules: on the inner display the on-demand split divider sits on the hinge in every pose (the active fold in book pose, the inactive hinge region while flat; see [split-view](split-view.md)); the outer display behaves as an iPhone.
- Run the `apple-hig` skill's `/duo` workflow stage by stage before Duo work.
- **The hinge in layout** (plan Phase 4, 2026-10-15). `EnvironmentValues.windowHinge` (HassDesign; the shell reads it once, `readsWindowHinge()`) is the one source. Every rule below is geometric (a hinge rect), never a device-name check, and is unit tested by feeding a rect measured on the simulator (hinge band 455.3 to 495.7 pt in a 951 pt window, content ending at the trailing bar's 868 pt).
  - **Even columns.** A `DynamicGridLayout` rounds its column count down to an even number (at least two) while a hinge is set, so no track pair straddles the fold ([dynamic-grid](../../patterns/dynamic-grid.md)).
  - **Chip gap.** A `ChipRail` (Home, Security, room pages) wraps in regular width and stops 24 pt short of the hinge (`ChipRailMetrics.hingeGap`, direction G: "the chip row stops 24pt short of the hinge"); the system's trailing vertical bar also covers about 83 pt and sits in the safe area.
  - **Two-column Home.** In unfolded landscape Home splits on the hinge (`HomeColumns`, built on `SplitPolicy.geometry`): chips and weather lead, cameras and guests trail, the hinge band stays empty (mockup n1-duo-unfolded). Cameras take the 2 x 2 layout in the trailing half. iPad landscape stays one column (n1-ipad-home), and unfolded portrait is one column.
  - **Quick Links** is the floating circle bottom trailing, which on the unfolded Duo sits in the trailing half, clear of the trailing bar.
  - Not device-verified on an unfolded simulator in this lane (see PROGRESS.md 2026-10-15); only unit tests cover the hinge rules.
- Window changes (fold, unfold, rotate) move an open detail between the trailing pane and a push, one run-loop turn after the window update, unanimated.
