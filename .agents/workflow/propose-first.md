# Propose first

> **What:** the gate between "I understand the problem" and "I'm writing the fix" for anything the owner will see or feel: a mockup and a recommendation come first, the build waits for the owner's pick. **Read when:** before writing code for any change to UI, layout, copy, motion, navigation or a shared pattern.

Owner rule (2026-10-23): for visible changes, show mockups and a proposal for review before changing code. It came out of the weather card header, the reconnecting spinner and the camera viewer, where the owner asked for "mockups and code changes for review" each time. The weather header ([doc](../design/weather-card-header.md)) is the model.

## When it applies

| Applies | Does not apply |
|---|---|
| Anything a person will see or feel change: layout, sizing, spacing, copy, icons, colour, materials, motion, haptics, navigation, sheet or detent behavior | Crashes and logic bugs with no visible difference |
| A new screen, control, tile, chip, sheet or setting | Performance, tests, tooling, docs, refactors that render the same pixels |
| A change to a shared pattern ([patterns](../patterns/README.md)), even if the reported bug is on one screen | Restoring behavior a spec or pattern doc already states; the fix is the spec |
| A fix with more than one reasonable visual answer | The option the owner has already chosen (build it) |
| | Unattended triage: see [Exceptions](#exceptions) |

When unsure whether a change is visible enough, propose. A one-screen proposal costs less than a rejected build.

## The proposal

One self-contained HTML file at `.agents/design/mockups/<topic>/<topic>.html`, headed `Proposal · <date>`, that opens in a browser with no network (light and dark, readable at phone width). In order:

1. **Cause or goal.** What is wrong or wanted, with the measured evidence (point sizes, the failing string, a screenshot), not a guess.
2. **Options.** At least two genuinely different answers when there is a design choice; if the fix is unambiguous, a before and after. Each at live size on the device families it affects (iPhone, iPhone Duo, iPad), at the default text size and an accessibility size, and in the states that break it (long text, empty, error, offline).
3. **Comparison.** A table against the owner's stated rules and the HIG, honest about what each option costs or gives up.
4. **Recommendation.** One option, the reason, and what it asks of the app (files touched, new motion, new tests, effect on shared components).
5. **Open questions.** Only what the owner must answer.

Share it where the owner is reading (the session, and a gallery artifact link if one exists), summarise it in a few lines, and **stop**.

## The gate

- Until the owner picks, write no production code and open no PR. Reading, measuring, a reproduction test and the mockup itself are fine; a throwaway prototype is fine to measure with, but it does not ship.
- "Just do it" from the owner for this change skips the gate for this change only.
- A lane or subagent that reaches a design choice stops and reports the proposal; it does not choose for the owner.
- Within the chosen option, the agent decides the details and records them.

## After the owner picks

1. Write or update `.agents/design/<topic>.md` ([weather-card-header.md](../design/weather-card-header.md) shows the shape): the bug or goal, the decision (owner, option, date), and the rules it adds. Update the pattern doc if a shared component changed.
2. Commit the mockup with the decision; it stays as the record of what was weighed. Link it from [design/README.md](../design/README.md).
3. Build, test and verify per the [change loop](change-loop.md). The PR names the proposal and the option chosen, and shows the built result beside the mockup.

## Exceptions

The unattended triage agent has no one to ask. Its standing rule ([triage-agent](triage-agent.md)) is to take the recommended option, post it as a `decision` comment and keep working, and to finish `needs_decision` only when the choice is irreversible or only the owner can make it. Its PR is the proposal; the owner can send it back.
