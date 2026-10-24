# Change loop

> **What:** the per-change procedure. **Read when:** before any code change.

1. **Source.** Read the React source for the surface (`ha-sfenton-react-dash/src/pages`, `src/components`, entity IDs in `src/constants`). Note entities, displayed states, services called and navigation edges.
2. **Spec.** Update `.agents/pages/<id>/spec.md` (platform-neutral) and the platform file (`ios.md`, `ipados.md`, `duo.md`, `watchos.md`).
3. **Pattern check.** If the behavior exists elsewhere, extend the canonical component in [patterns](../patterns/README.md).
4. **Propose.** Find the surface in the [mockup atlas](../design/mockups/README.md) first. If the change is visible, stop here: build a mockup page and a recommendation, share it, and wait for the owner's pick ([propose-first](propose-first.md)). Skip only for changes that render the same pixels.
5. **Implement** the chosen option in your lane's folders. Entity IDs go in `HassCore/Config`, never inline in views.
6. **Test.** Unit tests for logic in `HassCore`/`HassDesign`; UI and accessibility tests with each UI change.
7. **Review** your diff with `/swiftui-pro` ([how](swiftui-pro.md)) and fix what it finds in your files.
8. **Verify** on the simulator against the mockup, update the surface's atlas mockup (states, motion, a11y, status) in the same PR, then commit small and update [PROGRESS.md](../../PROGRESS.md).
