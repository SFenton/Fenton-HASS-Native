# Design decision

> **What:** how agents decide a design question the owner hasn't. **Read when:** a choice changes navigation, presentation or a shared pattern. Visible choices go through [propose-first](../../workflow/propose-first.md) before any code.

1. Check the HIG (`apple-hig` skill) and the web behavior.
2. Precedence: owner's explicit choice > HIG > web parity > convenience.
3. If the answer is owner-visible and the precedence above does not settle it, do not decide: propose mockups and a recommendation and wait ([propose-first](../../workflow/propose-first.md)).
4. Decide yourself only what the owner's choice, a registered pattern or the HIG already settles, or details inside the option they picked. Record the rule and its reason in the owning doc, and tell the owner in the thread or PR so they can override.
