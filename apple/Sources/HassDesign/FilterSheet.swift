import SwiftUI

/// A sort or filter sheet that edits a draft: Cancel discards, Apply commits, Reset restores defaults
/// (pattern: `.agents/patterns/filter-sheet.md`; web `ModalSheet` + `FilterSheetFooter`).
///
/// The caller owns the draft and decides what Apply and Reset do; the sheet supplies the chrome.
public struct FilterSheet<Content: View>: View {
    public var title: String
    /// Accessibility identifier prefix for the sheet's buttons, e.g. `recipes.sort`.
    public var identifier: String
    public var onApply: () -> Void
    public var onReset: () -> Void
    @ViewBuilder public var content: () -> Content
    @Environment(\.dismiss) private var dismiss

    /// Creates a sheet.
    public init(title: String, identifier: String, onApply: @escaping () -> Void, onReset: @escaping () -> Void, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.identifier = identifier
        self.onApply = onApply
        self.onReset = onReset
        self.content = content
    }

    public var body: some View {
        NavigationStack {
            Form {
                content()
                Section {
                    Button("Reset to Defaults", role: .destructive, action: onReset)
                        .frame(minHeight: HassTokens.minTarget)
                        .accessibilityIdentifier("\(identifier).reset")
                }
            }
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("\(identifier).cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        onApply()
                        dismiss()
                    }
                    .accessibilityIdentifier("\(identifier).apply")
                }
            }
        }
    }
}

/// A labelled 0...100 slider in steps of 5 that shows and speaks its value (web `RangeField`).
public struct PercentSlider: View {
    public var title: String
    @Binding public var value: Double
    public var identifier: String

    /// Creates a slider.
    public init(_ title: String, value: Binding<Double>, identifier: String) {
        self.title = title
        _value = value
        self.identifier = identifier
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                Spacer(minLength: HassTokens.Spacing.s)
                Text("\(Int(value))%").monospacedDigit().foregroundStyle(HassTokens.Ink.secondary)
            }
            Slider(value: $value, in: 0...100, step: 5)
                .accessibilityLabel(title)
                .accessibilityValue("\(Int(value)) percent")
                .accessibilityIdentifier(identifier)
        }
        .padding(.vertical, HassTokens.Spacing.xs)
    }
}
