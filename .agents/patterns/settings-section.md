# Settings section

> **What:** a settings page's header + description + controls block, and the pieces that go in it. **Read when:** building a settings-style page (Admin, Guests, Vacation, Sprinklers…).

- `SettingsSection(title:paragraphs:content:)` (`HassDesign/SettingsSection.swift`, web `SettingsSection.tsx`): `.title3` semibold header with the heading trait, each description paragraph as its own `.subheadline` text in `HassTokens.Ink.secondary`, then the content. Pages stack sections in a `ScrollView` with `Spacing.xl` between them.
- `InlineAlert(_:)`: a warning under the control it concerns (orange triangle, tinted rounded background, primary text); VoiceOver reads "Warning: …".
- `SelectableOptionRow`: one choice in a single-choice set (icon, label, description, checkmark; `.isSelected`; description as the hint). Lay several out with `DynamicGridLayout(minCellWidth: 300, maxColumns: 2)`. Web `ScheduleListRow`.
- Read-only entity values use the read-only entity tile ([entity-tile](entity-tile.md)).
