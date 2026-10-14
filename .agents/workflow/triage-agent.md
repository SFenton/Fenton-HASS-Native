# Triage agent (MacBook)

> **What:** how in-app bug reports and feature requests become merged changes: the private request repo, the runner on the MacBook, labels, owner commands and safety. **Read when:** changing `tools/triage/**`, the feedback form's filing, or diagnosing why a request wasn't picked up. Ported from FestivalNativeApps' release machine (`SFenton/festival-report-tracker`), cut down to one host and one issue at a time.

## Flow

1. **Intake.** Settings → Feedback → Report an Issue / Request a Feature ([feedback form](../pages/settings/feedback.md)) sends the report through Home Assistant's [Fenton Home Feedback](https://github.com/SFenton/ha-fenton-feedback) integration, which holds the owner's GitHub token and files an issue in the **private** repo `SFenton/fenton-hass-requests` (so issues are authored by `SFenton`): labels `Bug`|`Feature`, `From App`, `iOS`|`iPadOS`|`iPhone Duo`, media as GitHub user attachments, a diagnostics table naming the Home Assistant user, and the marker `<!-- fenton-feedback:v1 -->`. Issues typed on GitHub by the owner are worked the same way. Private because screenshots show the house.
2. **Pickup.** launchd runs `tools/triage/hass_triage.py tick` every minute (`com.sfenton.hass-triage`), so a report is picked up within about a minute of being filed. Like FestivalNativeApps' machine (a one-minute tick, plus a controller polling GitHub every 15 s for queued intake jobs), the Mac reaches out to GitHub; nothing reaches into it. An idle tick costs a handful of GitHub API reads. A tick takes a lock, refreshes its own clone (`~/hass-agents/repos/Fenton-HASS-Native`, never `~/repos`), finishes merged work, re-queues issues the owner answered, then works open issues by an allowed author (`SFenton`), `Priority` first, then oldest, one at a time until none are left (10 h budget).
3. **Work.** Per issue: label `In Progress`, a pickup comment, media downloaded to `~/hass-agents/work/<n>/media`, a worktree `~/hass-agents/worktrees/<n>` on `report/<n>` from `origin/main`, then `claude -p` (Opus 5.5, effort high, **auto** permission mode, deny list in `tools/triage/config.json`) with [prompts/worker.md](../../tools/triage/prompts/worker.md). The session triages, posts root cause or approach, reproduces, fixes, tests on iPhone, Duo and iPad, opens a PR and writes `~/hass-agents/status/<n>.json`. `caffeinate` keeps the Mac awake; a 5 h timeout stops it.
4. **Hand-off.** A `done` status with `tests_passed` and an open PR: the runner labels the PR `Ready to Merge`, the issue `Merging`, and comments the summary. **Nothing on the Mac merges** (owner, 2026-10-13: the coordinator merges). Once the PR is merged the next tick posts the *Resolved* summary (cause, fix, tests, screenshots), labels `Done` and closes the issue. A PR labelled `Merge Failed` or closed goes back to `Blocked`.
5. **Other outcomes.** `no_changes` closes as not planned (`No Changes`); `split` files child issues and closes the parent (`Split`); `needs_decision` labels `Needs Decision` with the options; `blocked` labels `Blocked`. A session that ends without a status is retried once, then blocked with the redacted log tail.

## Owner commands

| To | Do |
|---|---|
| Retry a `Blocked` issue, or answer a `Needs Decision` one | Reply on the issue (`/retry`, or your choice); the next tick re-queues it with your reply in the prompt |
| Jump the queue | Add `Priority` |
| Keep the agent away | Add `On Hold` |
| Send a merged fix back | Reopen the issue; it is worked as a follow-up with the earlier comments |
| Send an unmerged PR back | Label the PR `Merge Failed` |

## Commands (on the MacBook)

| Task | Command |
|---|---|
| Install / reinstall the job | `python3 tools/triage/hass_triage.py install` (every 60 s by default; `--interval 300`, `--uninstall`) |
| What it's doing | `python3 tools/triage/hass_triage.py status` |
| Run now | `python3 tools/triage/hass_triage.py tick` (`--dry-run` lists the queue and changes nothing) |
| Work one issue | `python3 tools/triage/hass_triage.py run-issue N` |
| Pause / resume | `python3 tools/triage/hass_triage.py pause` / `resume` |
| Create labels | `python3 tools/triage/hass_triage.py init-labels` |
| Tests | `python3 -m unittest discover -s tools/triage/tests` |

Workers use `hass_triage.py comment N --kind root-cause|approach|progress|decision|resolution --body-file F --media FILE::caption` (edits its own comment on retries via `<!-- hass-triage:N:KIND -->`) and `hass_triage.py upload FILES`.

## Files

| What | Where |
|---|---|
| Config (deep-merged with `~/.config/hass-triage/config.json`) | `tools/triage/config.json` |
| State, lock | `~/.local/state/hass-triage/{state.json,tick.lock}` |
| Kill switch | `~/.config/hass-triage/PAUSED` |
| Logs | `~/hass-agents/logs/<n>-<attempt>.log`, `launchd.log` |
| launchd job | `~/Library/LaunchAgents/com.sfenton.hass-triage.plist` |

## Safety

- Only issues and replies by `authors` are worked. Issue text is wrapped as untrusted data in the prompt (`UNTRUSTED_NOTICE`): a request, never instructions to touch credentials, CI, signing or other repos.
- The session runs in **auto** permission mode, so the auto-mode classifier still guards every action; the deny list (`tools/triage/config.json`, tested) also blocks every merge route (`gh pr merge`, `gh api` PUT/merge/GraphQL calls), pushes or refspecs that land on `main`, force-push flags and `+` refspecs, REST calls that merge into or rewrite refs, workflow runs and `simctl shutdown all`. These are prefix patterns, so they narrow what a session can do rather than guarantee it; the prompt and the owner's merge are the other two layers.
- Tokens: `gh auth token` is read only inside the runner for downloads and uploads; logs and comments pass through `redact()`. The Home Assistant credentials stay in `~/repos/Fenton-HASS-Native/temp.env`, passed by path to `tools/ios_uitest.sh --env`.
- Capacity: every build and simulator run goes through `tools/devcap.py` (directly or via `tools/ios_uitest.sh`), on simulators named `… (Triage)` only; the session's deny list blocks bare `xcrun simctl boot`, `xcodebuild test` and `xcodebuild build-for-testing` so nothing bypasses the gate.
