# iPhone Duo

> **What:** foldable iPhone adaptation. **Read when:** changing layout that a fold or hinge can cross.

- Rotates freely folded and unfolded (`FentonOrientationSupport` allows all orientations once `HingePresence` sees a hinge or vertical bar). Folded and unfolded portrait are single page; unfolded landscape may split ([split-view](split-view.md)).
- Carry over FestivalNativeApps' Duo rules: on the inner display the on-demand split divider sits on the hinge in every pose (the active fold in book pose, the inactive hinge region while flat; see [split-view](split-view.md)); the outer display behaves as an iPhone.
- Run the `apple-hig` skill's `/duo` workflow stage by stage before Duo work.
- Window changes (fold, unfold, rotate) move an open detail between the trailing pane and a push, one run-loop turn after the window update, unanimated.
