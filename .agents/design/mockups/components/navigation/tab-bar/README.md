# Floating tab bar (component)

> **What:** The five-tab bar: glass capsule on iPhone, vertical bar on the folded Duo, hidden at regular width. **Read when:** you touch MainTabView tabs, AppSection or the Chores badge.

- Mockup: [tab-bar.html](tab-bar.html) · shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/App/MainTabView.swift`, `apple/Sources/HassUI/App/Shell/AppSection.swift`, `apple/Sources/HassUI/Features/Chores/OverdueChoresBadge.swift`
- Spec: `.agents/design/direction-g.md`, `.agents/design/apple/iphone.md`, `.agents/design/apple/duo.md`, `.agents/design/motion.md` · Patterns: motion
- States covered: in-context (iPhone, folded Duo, iPad), each tab selected, badge, vertical, chores-with-badge, ax5
- Motion: tab cut, badge update
- Devices: iPhone, folded Duo, iPad portrait
- Open notes: The system speaks the badge after the tab name; "N overdue" is the flyout row's label only. Bar labels do not scale at AX5.
