# Port a page

> **What:** procedure for porting a web page. **Read when:** starting a page port.

1. Find the page in `ha-sfenton-react-dash/src/pages` and its entities in `src/constants`. Haiku can build the entity inventory.
2. Write `.agents/pages/<id>/spec.md`: layout, entities, states, services, navigation edges, with file:line citations.
3. Classify the page in [split-view](../../design/apple/split-view.md).
4. Add `HassCore/Config/<Area>Config.swift` with the entity IDs.
5. Build the screen in `HassUI/Features/<Area>/` from existing patterns; add new shared pieces to `HassDesign` only with a pattern doc.
6. Tests, simulator check, then update `pages/README.md` and PROGRESS.md.
