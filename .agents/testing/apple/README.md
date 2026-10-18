# Apple testing

> **What:** test phases, device matrix, accessibility rules and coverage bars (ported from FestivalNativeApps). **Read when:** adding or changing Swift code.

| File | Holds |
|---|---|
| [strategy.md](strategy.md) | Phases, accessibility tests with every change, certification gates |
| [accessibility.md](accessibility.md) | Audit rules and evidence |
| [devices.md](devices.md) | iPhone, iPhone Duo, iPad matrix and how to run it |
| [performance.md](performance.md) | Fast-scroll tests on a physical device, navigation cost (`tools/ios_navperf.sh`), telemetry and targets |
| [ha-companion.md](ha-companion.md) | The official Home Assistant app on our simulators, for comparison |

## Order-independent tests

A full `swift test` runs every `@MainActor` suite in one process, interleaved on the main actor, and a run-loop pump (`RunLoop.main.run`) runs other suites' work nested inside it. A test that passes alone with `--filter` but fails in the full run is depending on that timing or on process state. Run the full suite before calling such a test fixed (2026-10-16).

- **No wall-clock budgets for work to happen.** Wait for the condition (`settle(until:)`, or a bounded poll of the state), and count settle passes rather than seconds (`HostedWindow.settle`). A fixed sleep is fine only for asserting that nothing happens.
- **Production timeouts race the main actor too.** A `Task.sleep` whose timer already fired returns normally even if the task is cancelled before its continuation runs, so check `Task.checkCancellation()` after a timeout sleep. Cover the race by blocking the main actor past a shortened timeout (`CameraLiveViewTests.aFirstFrameBeatsATimeoutThatHasNotRunYet`).
- **Compare renders with a tolerance.** The first `ImageRenderer` render in a process is a level or two off on a few antialiased pixels, so byte-equal `Data` depends on which test rendered first. Compare channels with a small threshold (`ValetudoMapDrawingTests.differs`).
- **Only expect a difference the view draws.** A "this changes the pixels" check on a configuration that draws nothing new passes only by render noise; assert the no-op instead (a vacuum without room selection hatches nothing).

## Driving hosted windows (2026-10-16)

The UX bar is 95%, which needs the code behind taps, sheets and rows to run, not only the first screen. Three tools in `apple/Tests/HassUITests` do that on the macOS host:

- **Launch switches** (`withLaunch(environment:defaults:)` in `GalleryLaunchTests.swift`). Set the `FENTON_GALLERY_*` variables and launch arguments the journeys pass, host `ComponentGallery` in a real window and check what it drew (`HostedWindow.snapshot()`, `distinctColors`, `differs(from:)`). `GalleryLaunchMatrixTests` opens every sheet, tab, scenario and fixture each gallery offers and checks the sheet is up. A lazy `List` builds only the rows in view, so `scrollThrough()` wheel-scrolls the window or sheet to run the rows below the fold. Add a launch to the matrix when a gallery gains a switch.
- **`AXWindow`** (`AXDriver.swift`). Hosts a view and drives it through the accessibility tree: find by `accessibilityIdentifier` or label, `press`, `type(_:into:)`, read values and enabled state, and wait on them (`wait`, `waitFor`, `text(_:where:)`). It needs the test host to be a regular application and the process to be trusted for accessibility (`AXWindow.isAvailable`): flow suites carry `.enabled(if: AXWindow.isAvailable)`, so on a machine without that permission they skip and the coverage gate reads low rather than passing without them.
- **View-model tests** for logic that sits in a view (`LoginModel` was split out of `LoginView` for this): drive the model against a stubbed session (`LoginStubProtocol`) and host the view over it for each state.

Rules learned the hard way:

- **Presses are real mouse events, never `AXPress`.** An accessibility action in this process ends the test host (it exits through `swift_task_asyncMainDrainQueue`), and so does posting events to `NSApplication`. `AXWindow.press` scrolls the element into view, then sends mouse moved, down and up to the window straight after each other (an `await` between them lets another test's window take the key place and drops the click).
- **Reads run on the main actor.** In this process an accessibility query runs on the calling thread, and AppKit builds table cells there, so a background query trips its auto layout checks.
- **An inactive host swallows the first click.** The test host is not always the active application (another one has the front, the screen is locked), and AppKit takes the first click on an inactive window as the one that wakes it, unless the view accepts first mouse. `AXWindow` replaces `acceptsFirstMouse(for:)` on every view class under the window before it clicks, which made list rows, switches, bordered and destructive buttons, `onTapGesture` rows and drags all answer the same way whoever has the front. Without it a click works or not depending on which window the machine happens to have active. Menus (`Picker` pop-ups) are the exception: a click opens an `NSMenu` tracking loop that holds the main thread, so sweeps leave pop-ups, pickers, the photo and file panels, the share sheet and camera access alone (`ControlSweepTests.endsTheSweep`), and `SweepWatchdog` ends the host with the last press named if a sweep stops advancing for 240 s (a click or a read of the tree counts as advancing, so a loaded machine is not a hang).
- **Windows are told apart by position**, not title (SwiftUI renames a window after its navigation title): `AXWindow` gives each one its own origin, so another test's window with the same identifiers is not read.
- **Poll the state a press changes** (`press(_:until:)` retries at other points along the element), never a fixed sleep: a full run keeps the main actor busy for seconds at a time.

The hosted suites add about ten minutes to a full `swift test`; the gate's devcap hold is an hour.
