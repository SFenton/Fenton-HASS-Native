# Settings (tab root) (page)

> **What:** the Settings tab root as built: Vacation and To-Do, Appearance, the household topics, Home Assistant Settings, Performance and Feedback on the wallpaper. **Read when:** you change `HassUI/Features/Settings` or need the Settings list on any device.

- Mockup: [settings.html](settings.html) · shipped · reviewed 2026-10-23 (author self-check; skill reviewers replace it)
- Source: `apple/Sources/HassUI/Features/Settings/SettingsScreen.swift`, `SettingsTabRoot.swift`, `SettingsSectionHeader.swift`, `Appearance/AppearanceSettingsSection.swift`, `Feedback/FeedbackSettingsSection.swift`, `AppIcon/AppIconSettingsRow.swift`
- Spec: `.agents/pages/settings/ios.md`, `household.md`, `feedback.md`  · Patterns: settings-section, module-list, page-backdrop
- States covered: default, steph-viewer, blur-changed, icon-badge-off, icon-changed, icon-unsupported, reduce-transparency, offline, reconnecting, long-text, ax5 (loading, refreshing, empty and error do not exist).
- Motion: blur-slider (live value, no token), icon-badge-toggle (standard 0.3 s knob, state 0.6 s track). Transitions: push to Performance, Home Assistant cover, feedback and App Icon sheets.
- Devices: iPhone, Duo folded, unfolded portrait and landscape, iPad portrait and landscape (never splits).
- Helpers: `pages/settings/_settings-account.js`, `pages/settings/_settings-page.js` (shared builders and local symbols; promote-to-kit list in the mockup's Notes).
- Open notes: iPad list width (704 pt readable guide), separator inset and section spacing are unverified. Docs: split-view.md still lists Settings as a split.
