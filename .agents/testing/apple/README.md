# Apple testing

> **What:** test phases, device matrix, accessibility rules and coverage bars (ported from FestivalNativeApps). **Read when:** adding or changing Swift code.

| File | Holds |
|---|---|
| [strategy.md](strategy.md) | Phases, accessibility tests with every change, certification gates |
| [accessibility.md](accessibility.md) | Audit rules and evidence |
| [devices.md](devices.md) | iPhone, iPhone Duo, iPad matrix and how to run it |
| [performance.md](performance.md) | Fast-scroll tests on a physical device, telemetry and targets |
| [ha-companion.md](ha-companion.md) | The official Home Assistant app on our simulators, for comparison |

## Order-independent tests

A full `swift test` runs every `@MainActor` suite in one process, interleaved on the main actor, and a run-loop pump (`RunLoop.main.run`) runs other suites' work nested inside it. A test that passes alone with `--filter` but fails in the full run is depending on that timing or on process state. Run the full suite before calling such a test fixed (2026-10-16).

- **No wall-clock budgets for work to happen.** Wait for the condition (`settle(until:)`, or a bounded poll of the state), and count settle passes rather than seconds (`HostedWindow.settle`). A fixed sleep is fine only for asserting that nothing happens.
- **Production timeouts race the main actor too.** A `Task.sleep` whose timer already fired returns normally even if the task is cancelled before its continuation runs, so check `Task.checkCancellation()` after a timeout sleep. Cover the race by blocking the main actor past a shortened timeout (`CameraLiveViewTests.aFirstFrameBeatsATimeoutThatHasNotRunYet`).
- **Compare renders with a tolerance.** The first `ImageRenderer` render in a process is a level or two off on a few antialiased pixels, so byte-equal `Data` depends on which test rendered first. Compare channels with a small threshold (`ValetudoMapDrawingTests.differs`).
- **Only expect a difference the view draws.** A "this changes the pixels" check on a configuration that draws nothing new passes only by render noise; assert the no-op instead (a vacuum without room selection hatches nothing).
