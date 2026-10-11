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
- `FENTON_KEEP_BOOTED=1` leaves the simulator booted after the run. Use it for the Duo: shutting down resets the pose set in Device Hub. Device Hub poses can be scripted with FestivalNativeApps `tools/ios_sim.py` (`set_duo_pose`; register a non-Festival Duo in `HUB_DEVICE_NAMES` first, and don't use its `boot_exclusive`, which shuts down other simulators).
- On the folded Duo the tab bar is a vertical bar that XCUITest reports as a toolbar, and bar items such as Back can move into it. Find tabs through both (`tab(_:in:)`) and go back through `BackButton` or the leading-edge swipe (`goBack(in:)`), never `navigationBars.buttons.element(boundBy: 0)`.
