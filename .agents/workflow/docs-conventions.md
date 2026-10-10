# Docs conventions

> **What:** rules that keep `.agents` small and routable. **Read when:** adding or moving any `.agents` file.

| Rule | Detail |
|---|---|
| Header | Line 1 `# Title`; next non-empty line `> **What:** … **Read when:** …` |
| Routers | Every folder has a `README.md` linking every child, except `pages/<id>/` and `controls/<id>/` |
| One platform per file | `spec.md` is platform-neutral; Apple form-factor detail goes in `ios.md`, `ipados.md`, `duo.md`, `watchos.md` |
| Size | Soft budget 200 non-empty lines per file |
| Content | Durable rules, decisions and gotchas. No run logs; git history keeps those |
| Unknowns | Write `TODO(orchestrator): …` rather than guessing |
