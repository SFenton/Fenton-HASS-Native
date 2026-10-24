import SwiftUI

/// One date, time, or date-and-time picker in ``ScheduleDateFields``.
public struct ScheduleDateField: Identifiable {
    /// Which part of the moment the picker edits: the date, the time, or both in one row (the Calendar
    /// app's Starts/Ends idiom; HIG Pickers, "Date pickers").
    public enum Part: Sendable { case date, time, dateAndTime }

    public var label: String
    public var part: Part
    public var value: Date
    public var identifier: String
    /// Receives the picked moment; a date-only or time-only picker leaves the other part unchanged.
    public var onChange: (Date) -> Void
    /// The earliest moment the picker offers (an end picker passes its start), so an invalid pair cannot be picked
    /// (HIG Pickers: constrain the range rather than report the error afterwards).
    public var earliest: Date?
    /// The latest moment the picker offers (a start picker passes its end).
    public var latest: Date?
    public var id: String { identifier }

    /// The selectable range, or `nil` when the picker is unbounded.
    var bounds: ClosedRange<Date>? {
        guard earliest != nil || latest != nil else { return nil }
        let low = earliest ?? .distantPast
        // A saved value already outside the other bound must stay reachable, so the range never inverts.
        return low...max(latest ?? .distantFuture, low)
    }

    /// This field limited to `earliest...latest` (either may be `nil`).
    public func limited(from earliest: Date? = nil, to latest: Date? = nil) -> ScheduleDateField {
        var copy = self
        copy.earliest = earliest
        copy.latest = latest
        return copy
    }

    /// Creates a field.
    public init(label: String, part: Part, value: Date, identifier: String, onChange: @escaping (Date) -> Void) {
        self.label = label
        self.part = part
        self.value = value
        self.identifier = identifier
        self.onChange = onChange
    }
}

/// Date and time pickers for schedules: one combined picker per moment, or a date and a time (pattern: `.agents/patterns/schedule-date-fields.md`;
/// web `NativePickerField` pairs in `ScheduleConfirmationForm`).
///
/// Each field is a labeled compact `DatePicker` on a material row, two per row when the width allows.
/// Fields that write to Home Assistant on change pass a `commitDelay`: the picker shows the new value at
/// once and reports it only after the user stops scrolling the wheels, so one adjustment is one service call.
public struct ScheduleDateFields: View {
    public var fields: [ScheduleDateField]
    public var commitDelay: Duration?

    /// Creates the fields.
    /// - Parameters:
    ///   - fields: The pickers, in reading order.
    ///   - commitDelay: Report changes only after this much quiet (`nil` reports every change at once).
    public init(fields: [ScheduleDateField], commitDelay: Duration? = nil) {
        self.fields = fields
        self.commitDelay = commitDelay
    }

    public var body: some View {
        DynamicGridLayout(minCellWidth: 320, maxColumns: 2, spacing: HassTokens.Spacing.s) {
            ForEach(fields) { field in
                ScheduleDatePicker(field: field, commitDelay: commitDelay)
            }
        }
    }
}

extension ScheduleDateField.Part {
    /// The picker's components.
    var components: DatePickerComponents {
        switch self {
        case .date: .date
        case .time: .hourAndMinute
        case .dateAndTime: [.date, .hourAndMinute]
        }
    }
}

/// One picker, holding a draft while a delayed commit is pending.
struct ScheduleDatePicker: View {
    var field: ScheduleDateField
    var commitDelay: Duration?

    @State private var draft: Date?
    /// A pick not yet reported; sent when the view goes away rather than lost.
    @State private var pending: Date?
    @State private var commit: Task<Void, Never>?
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // Label and picker side by side when the label fits on one line, else the picker drops below
        // it (narrow iPad sheet columns, accessibility sizes); the label never truncates.
        ViewThatFits(in: .horizontal) {
            if !typeSize.isAccessibilitySize {
                HStack(spacing: HassTokens.Spacing.s) {
                    label.fixedSize()
                    Spacer(minLength: 0)
                    picker
                }
            }
            VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
                label.fixedSize(horizontal: false, vertical: true)
                picker
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.body)
        .foregroundStyle(HassTokens.Ink.primary)
        .frame(minHeight: HassTokens.minTarget)
        .padding(.horizontal, HassTokens.Spacing.m)
        .padding(.vertical, HassTokens.Spacing.xs)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: HassTokens.Radius.chip, style: .continuous))
            // The saved value moved (an echo or another device): drop the draft.
            .onChange(of: field.value) { _, _ in draft = nil }
            .onDisappear(perform: flush)
    }

    private var label: some View { Text(field.label) }

    private var picker: some View {
        pickerControl
            .labelsHidden()
            .accessibilityLabel(field.label)
            .accessibilityIdentifier(field.identifier)
    }

    @ViewBuilder private var pickerControl: some View {
        if let bounds = field.bounds {
            DatePicker(field.label, selection: selection, in: bounds, displayedComponents: field.part.components)
        } else {
            DatePicker(field.label, selection: selection, displayedComponents: field.part.components)
        }
    }

    /// Reports a pick still waiting out the quiet time, so closing the sheet right after scrolling does not lose it.
    private func flush() {
        commit?.cancel()
        if let picked = pending {
            pending = nil
            field.onChange(picked)
        }
    }

    private var selection: Binding<Date> {
        Binding {
            draft ?? field.value
        } set: { picked in
            guard let commitDelay else {
                field.onChange(picked)
                return
            }
            draft = picked
            pending = picked
            commit?.cancel()
            let report = field.onChange
            commit = Task { @MainActor in
                try? await Task.sleep(for: commitDelay)
                guard !Task.isCancelled else { return }
                pending = nil
                report(picked)
                // If Home Assistant never echoes it, fall back to the saved value.
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                draft = nil
            }
        }
    }
}
