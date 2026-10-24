# hig-voiceover handoff (branch claude/hig-voiceover-dcbaaf)
Bucket "VoiceOver & accessibility", 78 fixes. Brief: primary checkout build/hig-bucket-brief.md.

## Done in code (path A, uncommitted until tests green; see git log)
- Selection as trait: AppIconChoiceButton (.isSelected, no "Selected" value); Media source tiles use GlassTile.Kind.selection; Settings Household rows .isLink.
- Content not hints: SelectableOptionRow detail -> accessibilityValue; recipe ingredient row -> RecipeFormatting.spokenValue (adds "Match unsure").
- Duplicate Edit removed from TodoListSection custom actions.
- onTapGesture -> Button: InventoryRow copy; BedroomRow(onOpen:openIdentifier:) for WakeLightSheet and BedSideSheet alarm rows (nested Button+Toggle split).
- Dead sensors spoken as unavailable on room overview cards (RoomOverview.spokenSubtitle); no visual change.
- Reduce Transparency: Settings list rows opaque (HassTokens.Surface.moduleThin(reduceTransparency:)).
- Tests: VoiceOverSemanticsTests, RoomOverviewTests, RecipeFormattingTests, AppIconPickerTests, HomePagesViewTests.

## Skipped with reason
- WeatherCardContent / LoginFields onTapGesture: the AT element is already a real Button (cardButton) / the field; the gesture is a touch convenience.
- ContentGate screenChanged: gate is also used for results reloads (screenChanged would steal focus).

## Next (not started)
- Announcements (UIAccessibility.post/AccessibilityNotification.Announcement): session-expired, sign-in arrival, reconnecting chip, info-box notices, TodoSheetErrorSection, feedback blockingReason, fan timer value (round to minutes).
- Hints: chip-rail (StatusRail.swift:59), vacuum action detail (VacuumComponents.swift:236), Groceries tiles hint, badge label on tab item, QuickLinksButton label, watch-app decorative image hidden.
- custom light inert swatch (disabled instead of allowsHitTesting), GlassStateTile -> .state kind, vacuums ModuleRow Toggle label, climate checklist double announce, ImageCard hidden Button.
- PROPOSALS needed (visible): 8->12 pt mode spacing (security), inventory cart/chevron spacing, thermostat +/- alternative, vacuum zoom buttons, brightness tile power switch, flyout drag, ha-web-page back gesture, unavailable room tile dimming (isUnavailable disables navigation: needs owner call), differentiate-without-colour weekday chips.
- Mockup `reviews` flips fix->pass; PROGRESS.md line; mockups_check.py / mockups_index.py --check.
