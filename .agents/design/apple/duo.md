# iPhone Duo

> **What:** foldable iPhone adaptation. **Read when:** changing layout that a fold or hinge can cross.

- Rotates freely folded and unfolded (`FentonOrientationSupport` allows all orientations once `HingePresence` sees a hinge or vertical bar). Folded and unfolded portrait are single page; unfolded landscape may split ([split-view](split-view.md)).
- Carry over FestivalNativeApps' Duo rules: inner display in book pose aligns the on-demand split divider to the hinge; flat pose uses the free-space midpoint; outer display behaves as an iPhone.
- Run the `apple-hig` skill's `/duo` workflow stage by stage before Duo work.
- Window changes (fold, unfold, rotate) move an open detail between the trailing pane and a push, one run-loop turn after the window update, unanimated.
