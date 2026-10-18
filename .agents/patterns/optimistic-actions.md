# Optimistic actions

> **What:** how a control shows its new value at once and stays honest. **Read when:** a control calls a service and should not wait for Home Assistant before it looks changed.

- **Component:** `OptimisticActions` (`HassCore/Optimism/OptimisticActions.swift`) over `OptimisticOverlay` (`HassCore/Entities/OptimisticOverlay.swift`). Web source: `useOptimisticState` and `runOptimisticServiceCommand` (`ha-sfenton-react-dash@f5a7bf9:src/hooks/useOptimisticState.ts`, `src/components/hass/optimisticActionState.ts`).
- **Behavior (web parity):**
  - `perform(call, showing: [OptimisticIntent], resetting: [OptimisticReset])` shows the intents immediately, then sends the call.
  - The pending value clears quietly when the live value matches it (`.confirmation`), or on any live change (`.liveChange`).
  - If neither happens, it reverts after `revertAfter` (default `OptimisticActions.defaultRevert`, 2 s, web `DEFAULT_OPTIMISTIC_REVERT_MS`).
  - A failed call rolls back exactly the values it committed, using generations, so an older failure never undoes a newer tap. There is no error state between the optimistic value and the live one.
- **Clear rule:**
  - Use `.confirmation` for selects, modes and switches Home Assistant echoes as-is.
  - Use `.liveChange` when something else may override the result. Lights under Presence Based Lighting are the example: if the light reverts, the tile follows the truth instead of holding the tapped value.
- **Live source:** `init(store:rules:caller:)` tracks entity states. `init(rules:caller:live:)` takes any observable value, such as an attribute (`fan_mode`) or a derived key.
- **Reading:** views read `shown(key)`. `isPending(key)` tells a control it is waiting, for example to dim a spinner. Do not show an error UI for a pending value.
- **Pending outline (not built, 2026-10-17).** The sign-in lane was asked for a faint outline on a tile between the tap and the confirmation. `isPending` exists for a control's own dimming, but a tile outline needs a new `GlassTile` input every controller would pass, and "no error UI between the optimistic value and the live one" is the pattern's rule; the planner decides whether to add it as a tile-wide pattern.
- **Telemetry:** each call is a `ServiceCall` signpost, each confirmation an `OptimisticConfirm` interval, and rollbacks are counted (`optimistic.rollbacks`).
- **Adopting:**
  - New controllers use `OptimisticActions`.
  - Existing controllers that wire `OptimisticOverlay` + `observeLive` + `perform` by hand (Climate, room devices, vacuums, sprinklers, bed sides, household settings, Vacation, Solo Trip) move over when next touched. Their behavior is already identical.
  - `try?` around a service call that shows an optimistic value is a review finding: route it through `perform` so a failure rolls back.
- **Tests:** `Tests/HassCoreTests/OptimisticActionsTests.swift`. Use `RecordingCaller` (`failNext`) with `ManualScheduler`.
