import SwiftUI

/// A sort or filter sheet that edits a draft and applies it on demand (web `ModalActionFooter` with
/// Reset + Apply in the recipe and inventory sort/filter modals). Pattern: `.agents/patterns/floating-actions.md`.
///
/// The caller owns the draft: it passes its form rows as `content`, commits the draft in `onApply` and
/// restores defaults in `onReset`. Cancel (or a swipe down) drops the draft.
public struct FilterSheet<Content: View>: View {
    public var title: String
    /// Apply is enabled only when the draft differs from what is applied.
    public var canApply: Bool
    /// Reset is enabled only when the draft differs from the defaults.
    public var canReset: Bool
    public var onApply: () -> Void
    public var onReset: () -> Void
    @ViewBuilder public var content: () -> Content

    @Environment(\.dismiss) private var dismiss

    /// Creates a sheet.
    public init(title: String, canApply: Bool, canReset: Bool, onApply: @escaping () -> Void, onReset: @escaping () -> Void,
                @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.canApply = canApply
        self.canReset = canReset
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
                        .disabled(!canReset)
                        .accessibilityIdentifier("filterSheet.reset")
                }
            }
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("filterSheet.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        onApply()
                        dismiss()
                    }
                    .disabled(!canApply)
                    .accessibilityIdentifier("filterSheet.apply")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #if os(iOS)
        // Opaque, not glass: at the medium detent the page's floating buttons otherwise show through and fail contrast.
        .presentationBackground(Color(.systemGroupedBackground))
        #endif
    }
}

/// A single-choice row with a title, optional subtitle and a checkmark (web radio rows in sort/filter modals).
public struct FilterOptionRow: View {
    public var title: String
    public var subtitle: String?
    public var isSelected: Bool
    public var action: () -> Void

    /// Creates a row.
    public init(title: String, subtitle: String? = nil, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: HassTokens.Spacing.m) {
                VStack(alignment: .leading, spacing: HassTokens.Spacing.xs) {
                    Text(title).foregroundStyle(HassTokens.Ink.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(HassTokens.Ink.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.tint)
                    .opacity(isSelected ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: HassTokens.minTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
