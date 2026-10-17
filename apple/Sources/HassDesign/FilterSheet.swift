import SwiftUI

/// A sort or filter sheet that edits a draft and applies it on demand (web `ModalActionFooter` with
/// Reset + Apply in the recipe and inventory sort/filter modals). Pattern: `.agents/patterns/floating-actions.md`.
///
/// The caller owns the draft: it passes its form rows as `content`, commits the draft in `onApply` and
/// restores defaults in `onReset`. Cancel (or a swipe down) drops the draft.
public struct FilterSheet<Content: View>: View {
    public var title: String
    /// A one-line state under the title, such as "2 Filters On" (``SwiftUICore/View/sheetSubtitle(_:)``).
    public var subtitle: String?
    /// Apply is enabled only when the draft differs from what is applied.
    public var canApply: Bool
    /// Reset is shown only when the draft differs from the defaults.
    public var canReset: Bool
    public var onApply: () -> Void
    public var onReset: () -> Void
    /// How tall the sheet opens: as tall as its rows by default (owner, 2026-10-16), so a short Sort sheet is short and
    /// a long Filter sheet reaches the large detent and scrolls.
    public var height: HassSheetHeight
    @ViewBuilder public var content: () -> Content

    @Environment(\.dismiss) private var dismiss

    /// Creates a sheet.
    public init(title: String, subtitle: String? = nil, canApply: Bool, canReset: Bool, onApply: @escaping () -> Void,
                onReset: @escaping () -> Void, height: HassSheetHeight = .fitted, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.canApply = canApply
        self.canReset = canReset
        self.onApply = onApply
        self.onReset = onReset
        self.height = height
        self.content = content
    }

    public var body: some View {
        NavigationStack {
            Form {
                content()
                // Shown only when there is something to reset: a disabled row fails the contrast audit. A list row in
                // the action tint (blue), as in the mockups (n5 Filter Recipes; direction G, Sheets: "Reset is a list
                // row"). Never red: resetting filters is not destructive (HIG Buttons: reserve red for destructive
                // actions; owner, 2026-10-16).
                if canReset {
                    Section {
                        Button(action: onReset) {
                            // The label wraps and the row grows at AX5: the system Form button clipped its title.
                            Text("Reset to Defaults")
                                .foregroundStyle(HassTokens.Ink.action)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, minHeight: HassTokens.minTarget, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("filterSheet.reset")
                    }
                }
            }
            // The sheet's own header treatment: no material band behind the title, rows fade out under it
            // (owner, 2026-10-16: "Filter Recipes shows a translucent background under its header").
            .modalChrome()
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .sheetSubtitle(subtitle)
            // An edit sheet (direction G, Sheets): circle x Cancel leading drops the draft, the filled check applies it.
            .toolbar {
                SheetCancelItem(identifier: "filterSheet.cancel") { dismiss() }
                SheetConfirmItem("Apply", isEnabled: canApply, identifier: "filterSheet.apply") {
                    onApply()
                    dismiss()
                }
            }
        }
        // The system appearance, the grabber, the iPad form size and the fitted height
        // (``SwiftUICore/View/hassSheet(_:height:appearance:fitKey:)``), keyed by title so the Sort and Filter sheets
        // remember their own heights.
        .hassSheet(.form, height: height, fitKey: "FilterSheet.\(title)")
    }
}

/// A titled `Form` section for a filter sheet. Use it instead of `Section("…")`: the system header's
/// secondary label measured 3.1:1 on the sheet's grouped background. Direction G's sheet header over an inset list is
/// 15 Semibold secondary (`.agents/design/direction-g.md`, Type), drawn in ``FormHeader``'s readable secondary ink.
public struct FilterSection<Content: View>: View {
    public var title: String
    @ViewBuilder public var content: () -> Content

    /// Creates a section.
    public init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    public var body: some View {
        Section {
            content()
        } header: {
            FormHeader(title)
                .font(.subheadline.weight(.semibold))
                .textCase(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
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
                        // Secondary ink (direction G, Colour). It measured 4.2:1 on a light iPad sheet's rows; sheets are
                        // dark now, where it is about 8:1 on the `#2C2C2E` row.
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(HassTokens.Ink.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(HassTokens.Ink.action)
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
