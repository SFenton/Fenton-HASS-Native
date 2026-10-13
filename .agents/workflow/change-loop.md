# Change loop

> **What:** the per-change procedure. **Read when:** before any code change.

1. **Source.** Read the React source for the surface (`ha-sfenton-react-dash/src/pages`, `src/components`, entity IDs in `src/constants`). Note entities, displayed states, services called and navigation edges.
2. **Spec.** Update `.agents/pages/<id>/spec.md` (platform-neutral) and the platform file (`ios.md`, `ipados.md`, `duo.md`, `watchos.md`).
3. **Pattern check.** If the behavior exists elsewhere, extend the canonical component in [patterns](../patterns/README.md).
4. **Implement** in your lane's folders. Entity IDs go in `HassCore/Config`, never inline in views.
5. **Test.** Unit tests for logic in `HassCore`/`HassDesign`; UI and accessibility tests with each UI change.
6. **Review** your diff with `/swiftui-pro` ([how](swiftui-pro.md)) and fix what it finds in your files.
7. **Verify** on the simulator, then commit small and update [PROGRESS.md](../../PROGRESS.md).
