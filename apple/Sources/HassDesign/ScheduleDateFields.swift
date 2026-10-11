import SwiftUI

/// One date or time picker in ``ScheduleDateFields``.
public struct ScheduleDateField: Identifiable {
    /// Which part of the moment the picker edits.
    public enum Part: Sendable { case date, time }

    public var label: String
    public var part: Part
    public var value: Date
    public var identifier: String
    /// Receives the picked moment (the other part unchanged by the picker).
    public var onChange: (Date) -> Void
    public var id: String { identifier }

    /// Creates a field.
    public init(label: String, part: Part, value: Date, identifier: String, onChange: @escaping (Date) -> Void) {
        self.label = label
        self.part = part
        self.value = value
        self.identifier = identifier
        self.onChange = onChange
    }
}

/// Paired date and time pickers for schedules (pattern: `.agents/patterns/schedule-date-fields.md`;
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
        DynamicGridLayout(minCellWidth: 260, maxColumns: 2, spacing: HassTokens.Spacing.s) {
            ForEach(fields) { field in
                ScheduleDatePicker(field: field, commitDelay: commitDelay)
            }
        }
    }
}

/// One picker, holding a draft while a delayed commit is pending.
struct ScheduleDatePicker: View {
    var field: ScheduleDateField
    var commitDelay: Duration?

    @State private var draft: Date?
    @State private var commit: Task<Void, Never>?

    var body: some View {
        DatePicker(field.label, selection: selection, displayedComponents: field.part == .date ? .date : .hourAndMinute)
            .font(.body)
            .foregroundStyle(HassTokens.Ink.primary)
            .frame(minHeight: HassTokens.minTarget)
            .padding(.horizontal, HassTokens.Spacing.m)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: HassTokens.Radius.chip, style: .continuous))
            .accessibilityIdentifier(field.identifier)
            // The saved value moved (an echo or another device): drop the draft.
            .onChange(of: field.value) { _, _ in draft = nil }
            .onDisappear { commit?.cancel() }
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
            commit?.cancel()
            let report = field.onChange
            commit = Task { @MainActor in
                try? await Task.sleep(for: commitDelay)
                guard !Task.isCancelled else { return }
                report(picked)
                // If Home Assistant never echoes it, fall back to the saved value.
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                draft = nil
            }
        }
    }
}
