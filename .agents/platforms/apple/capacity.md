# Simulator and build capacity

> **What:** how lanes share the Mac's simulators, devices and compile capacity. **Read when:** booting a simulator, driving a device, or running a heavy build or test.

Many lanes (this repo's and FestivalNativeApps') run on one Mac. Every simulator, physical device and heavy compile goes through `tools/devcap.py`, which hands out machine-wide slots first come, first served. When the Mac is full a lane waits its turn instead of booting another simulator.

`tools/devcap.py` is vendored byte for byte from `SFenton/FestivalNativeApps` `tools/devcap.py` (canonical copy, with `tools/tests/test_devcap.py`). Change it there first, then copy both files here; `python3 tools/devcap.py --version` must match. Worktrees keep the copy they branched with, so every copy from 1.2.1 on defers to the shared install at `~/.devcap/lib/devcap.py` when it is newer; after a devcap change merges, run `python3 tools/devcap.py install` from an up-to-date `main` checkout. A worktree with a copy older than 1.2.1 (or none) must rebase on `main`.

## Gates

| Gate | Slots | Taken by |
|---|---|---|
| `device-<UDID>` | 1 | `--sim UDID` or `--device UDID`: one lane per simulator or physical device |
| `simulator` | RAM / 16 GB, 1–6 (4 on this Mac; owner asked for more parallel lanes, 2026-10-15) | `--sim UDID`: one per simulator in use |
| `build` | cores / 4, 1–4 (2 on this Mac) | `--pool build`: `xcodebuild build-for-testing`, `swift build`/`swift test` |

Override a count with `DEVCAP_SLOTS_SIMULATOR=2` or `~/.devcap/config.json` (`{"simulator": 2}`); lowering it only affects new holders.

## Commands

```bash
# Run anything that boots or drives a simulator (device gate + simulator slot):
python3 tools/devcap.py run --sim "$UDID" --shutdown-on-timeout --purpose "rooms captures iphone" -- <command> [args...]

# Heavy compile:
python3 tools/devcap.py run --pool build --purpose "rooms build" -- xcodebuild build-for-testing ...

# Who holds what, and who is waiting:
python3 tools/devcap.py status
```

- `tools/ios_uitest.sh` already compiles once under `build` and runs each family under `--sim`; `tools/apple_coverage.sh` runs under `build`. Do not wrap them again (it is harmless: nested calls reuse the parent's gates through `DEVCAP_HELD`).
- Put the whole simulator sequence in one hold: boot, pose (Device Hub), install, run, capture. Leave the simulator warm between consecutive runs on the same device instead of shutting it down each time: a warm simulator counts against the slots, and devcap shuts it down after 60 s idle when another lane is waiting (5 min otherwise). `tools/ios_uitest.sh` does this with `--shutdown-on-timeout` for filtered runs (a hung run still shuts down) and shuts down after a full-suite run; pass `--shutdown`, or `FENTON_SHUTDOWN_SIM=1` for the script, on your last filtered run with a device.
- Simulators booted outside a hold are **unmanaged**: they count against the `simulator` slots, and after 5 minutes unmanaged the next waiter or finished hold shuts them down and closes Device Hub windows of devices nobody is using, including stale "Devices – No Selection" windows (owner decision, 2026-10-13). Simulators under Xcode's debugger are never shut down. So never boot or drive a simulator outside a hold; a direct `simctl boot` or `xcodebuild test` is shut down after 5 minutes. `python3 tools/devcap.py status` lists unmanaged simulators, and `python3 tools/devcap.py reap [--dry-run]` sweeps on demand. `DEVCAP_REAP_GRACE=off` or `DEVCAP_HUB=off` turn the sweeps off.
- Hold limits: `run` holds for 1800 s by default (`--hold`, `0` = no limit, max 7200; `tools/ios_uitest.sh` uses `FENTON_DEVCAP_HOLD`, default 3600). On overrun devcap kills the command's process group and exits 124. A wait gives up after `--wait` seconds (3600) with exit 75.
- Never hold `build` while waiting for a simulator (or the reverse) in separate calls; one `run` with every gate takes them in a fixed order and cannot deadlock.
- A dead holder's slot frees itself (the OS drops the lock). `~/.devcap/devcap.log` records every wait, acquire and release with the purpose and worktree.
- `tools/ios_uitest.sh` draws each family from a pool of identical simulators (`"iPad Pro 11-inch (M5)"`, `"… (pool 2)"`, …, one per simulator slot; `FENTON_SIM_POOL` overrides) through `python3 tools/devcap.py pick-sim`, so two lanes testing the iPad run on two iPads. A lane keeps its last pool member (warm, Duo pose intact) while it is free. Set `FENTON_SIM_IPHONE` / `FENTON_SIM_DUO` / `FENTON_SIM_IPAD` only to pin one specific device. Never `simctl shutdown all`, erase or reset another lane's device.
