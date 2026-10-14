# Schedule date fields

> **What:** date-and-time pickers for schedules. **Read when:** a page edits a start, end or alarm time.

- Canonical component: `HassDesign/ScheduleDateFields.swift` (`ScheduleDateFields`, `ScheduleDateField`). Web: `NativePickerField` pairs inside `ScheduleConfirmationForm` (`src/components/core`).
- **One picker per moment** (owner, 2026-10-13): a start or end is one `.dateAndTime` field ("Starts"/"Ends", "Departs"/"Returns", the Calendar app's idiom) showing the date and time buttons side by side; `.date` and `.time` remain for a value that is only one of them. Four fields for a range read as clutter.
- Each field is a labeled compact `DatePicker` (`.date`, `.hourAndMinute` or both) on a material row at least 44 pt tall, two per row when the width allows (`DynamicGridLayout`, min 320 pt: at 260 an iPad form sheet split into two ~270 pt columns where "Departure Date" no longer fitted beside its picker, 2026-10-11). HIG: Date pickers.
- The row is a wrapping `Text` label beside a `labelsHidden()` picker (labeled for VoiceOver); at accessibility Dynamic Type sizes the picker drops below the label. The picker's own label truncated ("Departure Time", text-clipped audit, iPhone 2026-10-11).
- Values are `Date`s; callers convert. Home Assistant wall-clock parts (`YYYY-MM-DD`, `HH:MM`) go through `WallClock` (HassCore); `ScheduleDateField(_:_:_:id:onChange:)` in `HassUI/Features/Vacation` keeps the other part when a single-part field changes and takes both from a `.dateAndTime` field.
- Fields that call a service on every change pass `commitDelay`: the picker shows the new value at once and reports it after that much quiet (so one wheel turn is one call). The draft clears when the saved value changes or 3 s after reporting.
- Validation messages go below the fields as inline alerts, not inside them.
- Consumers: Vacation Dates and Confirm Vacation, Solo Trip return and schedule. Planned: sprinklers start times, bed schedules.
