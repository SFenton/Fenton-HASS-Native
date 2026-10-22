# Token economy

> **What:** the rules and tools that keep Claude usage proportional to the work: no polling, short sessions, the right model, a short test loop. **Read when:** starting a lane or session, launching a build or test, or when the plan runs dry early. Evidence: [token-burn audit](../audit/token-burn-2026-10-22.md).

Cost is turns × context. Every turn re-reads the whole conversation, so a 700-turn session at 500 k tokens costs far more than five 140-turn sessions at 100 k, and a turn that only waits costs as much as one that works.

## Rules

1. **Never wait by polling.** No `until … sleep`, `for … seq … sleep`, `sleep` over 29 s or `tail -f`. Run long commands as `tools/bg_run.py LABEL -- COMMAND` with `run_in_background: true` and **end the turn**; the harness notifies you when it exits, and the notification is a digest of 30 lines, not a log. A `PreToolUse` hook (`tools/hooks/no_poll.py`, wired in `.claude/settings.json`) refuses the loops; `# poll-ok: reason` overrides it. Past five minutes a subagent's prompt cache has expired too, so each poll also rewrites its whole context.
2. **Read digests, not logs.** Open `build/runs/LABEL.log` only for a failure the digest cannot explain, and then `grep -n 'error:'` it. `INFRA` in a digest (Device Hub pose, hold timeout, unavailable simulator) is the machine, not the test: rerun once, then report it instead of diagnosing it again.
3. **One session per task, about 150 turns.** A task is a PR, a bug or a design decision. At roughly 150 turns or 200 k tokens, at a natural stop (a commit, a green run), write `build/handoff/<topic>.md` and continue in a fresh session from it. `tools/hooks/context_guard.py` reminds you at 150 k, 250 k and 400 k. A fresh session starts at 70 to 90 k, so do not split below a coherent task; batch the small related items of one area into one session.
4. **The right model.** The default for this repo is Sonnet (medium). Opus orchestrates, writes specs and design decisions, and is the final reviewer; it does not poll, run builds, read logs or do git chores. Compile-fix, test-fix, screenshot and PR lanes run on `coder` (Sonnet). Test re-runs, log reading, status checks and git chores run on `menial` (Haiku). Name the model in the brief; a spawn note that names none gets the default. A `PreToolUse` hook on `Agent` (`tools/hooks/agent_model.py`) refuses a spawn that would inherit Opus: use `subagent_type: coder` or `menial`, or pass `model: sonnet|haiku`; the final reviewer says `opus-ok: reason` in its prompt.
5. **Climb the test ladder.** Run the cheapest check that can fail: `swift test --filter` (seconds) → one `--quick` journey on iPhone → the journeys you touched on Duo and iPad → the full three-device suite and `tools/apple_coverage.sh`, **once per PR**, not after every edit.
6. **Do not rebuild a tool.** Lane setup, commit and PR, and log digests have scripts below; extend them.

## Handoff file

`build/handoff/<topic>.md` (ignored by git), 40 lines at most: branch and worktree, what is done and merged, what is half done, the next step, open failures with the test name and first error, commands already known to work. The next session reads this and `AGENTS.md`, nothing else.

## Tools

| Tool | Does |
|---|---|
| `tools/bg_run.py LABEL [--timeout S] -- CMD` | Runs CMD, log to `build/runs/LABEL.log`, prints the digest and exits with CMD's status (124 after `--timeout`) |
| `tools/test_digest.py LOG` | Result, failing tests with the first assertion, compile errors, infra causes; XCTest, Swift Testing and build logs |
| `tools/ios_uitest.sh --quick` | Skips `xcodegen` and the compile when nothing changed since the last build here; a filtered run holds its devcap slots 25 minutes, not 60 |
| `tools/lane_new.sh NAME` | Worktree `.claude/worktrees/NAME` on `claude/NAME` from `origin/main`, and the commands to run in it |
| `tools/ship.sh "Subject" [--pr]` | `git add -A`, commit with the trailer, push, optionally `gh pr create` with the assignee and footer; refuses on `main` and for env files, keys and profiles. Never merges |
| `tools/token_report.py [--since D]` | Tokens and relative cost by day and model, long sessions, poll turns, cache rewrites. Run it weekly; healthy is zero of each |

Hooks (`no_poll.py`, `context_guard.py`, `agent_model.py`) live in `tools/hooks/` and are wired in `.claude/settings.json`; each is a no-op when its script is missing, so older worktrees are not blocked. Tests: `python3 -m unittest tools.tests.test_digest tools.tests.test_hooks tools.tests.test_lane_ship tools.tests.test_token_report`.
