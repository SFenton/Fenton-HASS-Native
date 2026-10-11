# Schedule date fields

> **What:** paired date and time pickers for schedules. **Read when:** a page edits a start, end or alarm time.

- Canonical component: `HassDesign/ScheduleDateFields.swift` (`ScheduleDateFields`, `ScheduleDateField`). Web: `NativePickerField` pairs inside `ScheduleConfirmationForm` (`src/components/core`).
- Each field is a labeled compact `DatePicker` (`.date` or `.hourAndMinute`) on a material row at least 44 pt tall, two per row when the width allows (`DynamicGridLayout`, min 260 pt). HIG: Date pickers.
- Values are `Date`s; callers convert. Home Assistant wall-clock parts (`YYYY-MM-DD`, `HH:MM`) go through `WallClock` (HassCore); `ScheduleDateField(_:_:_:id:onChange:)` in `HassUI/Features/Vacation` keeps the other part when one changes.
- Fields that call a service on every change pass `commitDelay`: the picker shows the new value at once and reports it after that much quiet (so one wheel turn is one call). The draft clears when the saved value changes or 3 s after reporting.
- Validation messages go below the fields as inline alerts, not inside them.
- Consumers: Vacation Dates and Confirm Vacation, Solo Trip return and schedule. Planned: sprinklers start times, bed schedules.
