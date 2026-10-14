# Fix a reported issue

> **What:** the order of work for one request from the request repo (`SFenton/fenton-hass-requests`), whether the [triage agent](../../workflow/triage-agent.md) or a person works it. **Read when:** starting any reported bug or feature, before editing code. Condensed from FestivalNativeApps' skill of the same name.

1. **Pin the owner's intent.** Quote their words (issue body, media, their comments; the newest owner comment wins). Write one sentence: what they will see when it's done. If two readings lead to visibly different designs, decide with [design-decision](../design-decision/SKILL.md) and say which in the issue.
2. **Find the precedent before the fix.** Registered pattern ([patterns](../../patterns/README.md)) → the same behavior elsewhere in the app → the web dashboard (`ha-sfenton-react-dash`) → Apple HIG (cite the section). Fix the canonical component, never only the reported screen.
3. **Reproduce** on the reported device family (the issue's diagnostics give device, window size, text size and Home Assistant version): a unit test, a hosted render or the app on a simulator against the live server (`tools/ios_uitest.sh --env …`). Home Assistant is the source of truth: a server-side cause is explained, not patched in the app.
4. **Sweep the blast radius.** Every consumer of the changed behavior on iPhone, iPhone Duo and iPad; fix it or say why it's out of scope.
5. **Test the behavior shift.** Unit tests for logic; a UX journey and an accessibility audit (with the AX5 relaunch) on each affected device family ([testing](../../testing/apple/README.md)).
6. **Record rules, not history.** Update the pattern, page or control doc with the durable rule and the request number.
7. **Report** in the issue: cause or approach first, then what changed, the tests and screenshots per device. Reference the request with `Refs SFenton/fenton-hass-requests#N`; the runner closes it once the PR is merged.
