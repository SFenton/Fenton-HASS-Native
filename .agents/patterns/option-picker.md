# Option picker

> **What:** picking one value from a short list in a sheet. **Read when:** a control opens a list of options (input_select modes, HVAC modes).

- `OptionPickerSheet(title:options:selected:identifierPrefix:choose:)` (`HassDesign/OptionPickerSheet.swift`, web `OptionPickerDialog` with `presentation="sheet"`). Present it with `.presentationDetents([.medium, .large])`.
- Rows are 44 pt or taller, show the label, an optional `GradientSwatch`, and a checkmark on the current value; the current row carries `.isSelected`. Choosing calls `choose` only for a new value, then dismisses.
- Row identifiers are `<prefix>.<value>`.
- For two to five short choices inline on a page, prefer a segmented control or `Menu`; use this sheet when options need swatches or more room.
- First used by Custom Lights (Lighting Mode).
