# Device matrix

> **What:** the simulators every journey runs on and how to run them. **Read when:** running UI or accessibility tests.

| Family | Simulator (override env) | Orientation | Notes |
|---|---|---|---|
| iPhone | `iPhone 17 Pro` (`FENTON_SIM_IPHONE`) | Portrait only; `LayoutJourneyTests` proves it stays portrait | |
| iPhone Duo | `iPhone Duo` (`FENTON_SIM_DUO`) | Any | Needs Xcode 27.1+; set folded/unfolded and rotation in Device Hub before each run |
| iPad | `iPad Pro 11-inch (M5)` (`FENTON_SIM_IPAD`) | Any | Journeys rotate to landscape themselves |

```bash
tools/ios_uitest.sh --env /path/to/temp.env            # all three, one simulator at a time
tools/ios_uitest.sh --env /path/to/temp.env --only duo  # one family
```

- `--env` reads credentials locally and passes them as `TEST_RUNNER_FENTON_HASS_*`; signed-in journeys skip without them. Never print, log or commit them.
- One product simulator at a time; never touch other projects' simulators.
- Result bundles land in `apple/.build/uitest-<family>.xcresult` (git-ignored).
- `FENTON_KEEP_SIM=1` leaves the simulator booted after the run, so a Duo pose set in Device Hub survives into the next run (folded → unfolded portrait → unfolded landscape).
- Use the product Duo `FENTON_SIM_DUO="iPhone Duo (HASS)"`; the bare `iPhone Duo` device is shared.
- Device Hub can be driven by FestivalNativeApps' `tools/device_hub_ax.swift` helper (via `ios_sim.py`'s `set_duo_pose`, pointed at the HASS Duo) with the Accessibility permission; poses verify by which panel is lit (`simctl io --display=primary` outer, `primary-1` inner).
- Screenshots: set `TEST_RUNNER_FENTON_REDACT_PRIVATE=1` and `TEST_RUNNER_FENTON_CAPTURE_DIR=<dir>` and answer each `<name>.ready` with `xcrun simctl io <udid> screenshot [--display=…] <dir>/<name>.png` then `<name>.done`; the lit Duo panel is only reachable from the host.
- On the folded Duo the tab bar is a vertical bar that XCUITest reports as a toolbar, and bar items such as Back can move into it. Find tabs through both (`tab(_:in:)`) and go back through `BackButton` or the leading-edge swipe (`goBack(in:)`), never `navigationBars.buttons.element(boundBy: 0)`.
- On the unfolded Duo (Xcode 27.1, iOS 27.1 simulator) a test that throws `XCTSkip` hangs the runner in tear-down for about 3 minutes. xcodebuild then restarts it and reboots the simulator, which comes back **folded**, so the rest of the run silently tests the wrong pose. Run each unfolded pose with `-only-testing` for the journeys that apply to it (no skips), and check the pose after the run. Observed 2026-10-11 in five runs; runs without a skip finished in the pose they started in.
- Under load from several lanes' simulators, the host's simulator framebuffer can crash (`backboardd` in `SimFramebuffer __SFBConnectionConnect`, "Critical process backboardd crashed"), which also reboots the device. It is not an app failure: rerun the affected journeys.
