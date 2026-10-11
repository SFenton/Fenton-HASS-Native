# Add a control

> **What:** procedure for a reusable control. **Read when:** a control will be used on more than one screen.

1. Check [patterns](../../patterns/README.md) first; extend an existing component if one fits.
2. Specify states (on, off, pending, unavailable), accessibility (label, value, traits, actions) and the service it calls.
3. Implement in `HassDesign` (pure UI) taking values and closures, never an `EntityStore`.
4. Add a pattern doc row and unit tests for any state mapping.
