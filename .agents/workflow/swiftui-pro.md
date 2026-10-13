# SwiftUI Pro skill

> **What:** how this repo applies the vendored SwiftUI Pro skill. **Read when:** writing or reviewing any SwiftUI, or opening a PR that touches `apple/`.

The skill lives at [`.claude/skills/swiftui-pro`](../../.claude/skills/swiftui-pro/SKILL.md), vendored from [twostraws/swiftui-agent-skill](https://github.com/twostraws/swiftui-agent-skill) v2.0.0 (commit `f980071`, MIT, `LICENSE` beside it). Claude Code loads it from the repo, so every session in a checkout of `main` has `/swiftui-pro`. Other agents read `SKILL.md` and its `references/` directly.

## When to use it

| Moment | Do |
|---|---|
| Writing SwiftUI | Load the reference files for what you touch (views, data, navigation, accessibility, resizability) |
| Before opening a PR | Run `/swiftui-pro` on your diff; fix findings in your files, list the rest in the PR body |
| Reviewing a PR | Opus runs it as part of final review; a deprecated-API or accessibility finding is major |
| Deep performance work | Load `references/performance-plus.md` only for a requested or measured problem |

## Repo overrides

The skill's own rule is "check the deployment target first". Ours is **iOS 17 / watchOS 10**, Swift language mode 6.0, built with Xcode 27.1. Where the skill and the repo disagree, the repo wins:

| Skill rule | Here |
|---|---|
| iOS 26/27-only APIs (`ConcentricRectangle`, `safeAreaBar`, `ToolbarOverflowMenu`, `reorderable`, native `WebView`, `ForEach(x.enumerated())`) | Only behind `if #available`, with the iOS 17 path kept. Not a finding on its own |
| `Tab` API instead of `tabItem()` (iOS 18) | Required when the target reaches 18; until then `#available` or leave `tabItem` |
| Compiler-only rules (`@ContentBuilder`, `@Entry`, `alert(_:item:)`, `ForEach` in `toolbar`) | Apply: they back-deploy |
| One type per file | Applies to new files. Do not split existing files as a drive-by; do it in the owner lane |
| No computed `some View` helpers | Extract when a helper is reused or the body is long; small private helpers of one concern can stay |
| Shared constants enum for spacing, fonts, radii | That enum is `HassDesign` tokens. Extend it, never add a second one |
| Size-class layout, never device checks | Same as our `SplitPolicy` rule ([split-view](../design/apple/split-view.md)); iPhone stays portrait-locked |
| Prefer system sheets and `presentationDetents` | Use `.sheet` with `HassSheet` chrome ([modal-sheet](../patterns/modal-sheet.md)); detents follow that record |
| Apple HIG | Still cite the HIG via the `apple-hig` skill; SwiftUI Pro does not replace it |
