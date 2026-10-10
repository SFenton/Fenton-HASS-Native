# Screen classification and split view

> **What:** which screens are full width, split on demand, leading-pane only, or modal. **Read when:** adding a screen or changing how one is presented on iPad or Duo.

Split rules come from FestivalNativeApps `.agents/design/apple/split-view.md`: a page starts full width; selecting an item splits it 50/50 at the content midpoint (Duo: the hinge) with the detail in the trailing half; Close or Back returns to full width. Splits apply only in landscape regular width with each half ≥ 360 pt. Portrait and compact width push.

| Kind | Screens |
|---|---|
| Always full width, push | Home, Security, Climate, Chores, room pages, Food & Recipes |
| Split on demand | Chores lists → item detail; Food hub → Pantry, Fridge, Freezer, Spice Rack, Cabinet; Recipes → recipe |
| Leading pane, detail on the right | Settings (iPad/Duo): list stays left, topic opens right, placeholder when nothing is selected |
| Sheet | Status chip sheets (lights/rooms, security system, climate, occupancy, contacts), light and climate controls, Daily Report, to-do edit |
| Full-screen modal | Camera viewer, Home Assistant backend settings (web view), sign-in |

TODO(orchestrator): confirm Chores and Food splits with the owner once those pages are ported.
