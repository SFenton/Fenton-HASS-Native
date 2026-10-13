# Simulator and build capacity

> **What:** how lanes share the Mac's simulators, devices and compile capacity. **Read when:** booting a simulator, driving a device, or running a heavy build or test.

Many lanes (this repo's and FestivalNativeApps') run on one Mac. Every simulator, physical device and heavy compile goes through `tools/devcap.py`, which hands out machine-wide slots first come, first served. When the Mac is full a lane waits its turn instead of booting another simulator.

`tools/devcap.py` is vendored byte for byte from `SFenton/FestivalNativeApps` `tools/devcap.py` (canonical copy, with `tools/tests/test_devcap.py`). Change it there first, then copy both files here; `python3 tools/devcap.py --version` must match.

## Gates

| Gate | Slots | Taken by |
|---|---|---|
| `device-<UDID>` | 1 | `--sim UDID` or `--device UDID`: one lane per simulator or physical device |
| `simulator` | RAM / 20 GB, 1–4 (3 on this Mac) | `--sim UDID`: one per booted simulator |
| `build` | cores / 4, 1–4 (2 on this Mac) | `--pool build`: `xcodebuild build-for-testing`, `swift build`/`swift test` |

Override a count with `DEVCAP_SLOTS_SIMULATOR=2` or `~/.devcap/config.json` (`{"simulator": 2}`); lowering it only affects new holders.

## Commands

```bash
# Run anything that boots or drives a simulator (device gate + simulator slot):
python3 tools/devcap.py run --sim "$UDID" --shutdown --purpose "rooms captures iphone" -- <command> [args...]

# Heavy compile:
python3 tools/devcap.py run --pool build --purpose "rooms build" -- xcodebuild build-for-testing ...

# Who holds what, and who is waiting:
python3 tools/devcap.py status
```

- `tools/ios_uitest.sh` already compiles once under `build` and runs each family under `--sim`; `tools/apple_coverage.sh` runs under `build`. Do not wrap them again (it is harmless: nested calls reuse the parent's gates through `DEVCAP_HELD`).
- Put the whole simulator sequence in one hold: boot, pose (Device Hub), install, run, capture. Pass `--shutdown` so devcap shuts the simulator down before releasing it, even after a hold timeout; a simulator left booted outside a hold uses memory without a slot. `tools/ios_uitest.sh` does this unless `FENTON_KEEP_SIM=1`, which keeps a pose alive into the next run.
- Simulators booted outside a hold are **unmanaged**: they count against the `simulator` slots, and after 5 minutes unmanaged the next waiter or finished hold shuts them down and closes Device Hub windows of devices nobody is using, including stale "Devices – No Selection" windows (owner decision, 2026-10-13). Simulators under Xcode's debugger are never shut down. So never boot or drive a simulator outside a hold; a direct `simctl boot` or `xcodebuild test` is shut down after 5 minutes. `python3 tools/devcap.py status` lists unmanaged simulators, and `python3 tools/devcap.py reap [--dry-run]` sweeps on demand. `DEVCAP_REAP_GRACE=off` or `DEVCAP_HUB=off` turn the sweeps off.
- Hold limits: `run` holds for 1800 s by default (`--hold`, `0` = no limit, max 7200; `tools/ios_uitest.sh` uses `FENTON_DEVCAP_HOLD`, default 3600). On overrun devcap kills the command's process group and exits 124. A wait gives up after `--wait` seconds (3600) with exit 75.
- Never hold `build` while waiting for a simulator (or the reverse) in separate calls; one `run` with every gate takes them in a fixed order and cannot deadlock.
- A dead holder's slot frees itself (the OS drops the lock). `~/.devcap/devcap.log` records every wait, acquire and release with the purpose and worktree.
- Give each lane its own simulator (`FENTON_SIM_IPHONE="iPhone 17 Pro (Rooms)"`); lanes that share one queue on its device gate. Never `simctl shutdown all`, erase or reset another lane's device.
