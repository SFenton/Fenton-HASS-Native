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
- iPhone Duo poses (seen 2026-10-11): the simulator boots folded, and `tools/ios_uitest.sh` shuts it down after a run, so set the pose again before each run. Device Hub's unfold from a fresh boot gives unfolded **landscape**; rotate left from there for unfolded portrait. `ios_sim.set_duo_pose` often reports "unknown" under load, so confirm the pose by which panel is lit (`simctl io <udid> screenshot --display=primary` is the outer panel, `primary-1` the inner) and its aspect, before and after the run.
- Host captures (`FENTON_CAPTURE_DIR`) use `simctl io screenshot --display=primary-1` for the unfolded Duo; XCUIScreen captures the dark outer panel there.
- iPad host captures (`simctl io screenshot`) can return a rotated framebuffer: a "portrait" capture came back landscape-shaped. For iPad, use the `XCTAttachment` from the result bundle instead (`xcrun xcresulttool export attachments`), named `<name>-<orientation>` (seen 2026-10-12).
- After a mid-run crash restart (`Restarting after unexpected exit`), the Duo comes back **folded**, and its host captures go black on `primary-1`. Treat results after the restart as invalid for an unfolded pose; split unfolded runs into small `-only-testing` groups. Device Hub verification often reads "unknown"; confirm the pose by panel brightness (inner lit and outer dark means unfolded).
