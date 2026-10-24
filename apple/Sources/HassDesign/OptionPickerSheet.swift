import SwiftUI

/// A sheet that picks one option from a short list (web `OptionPickerDialog` with `presentation="sheet"`;
/// pattern: `.agents/patterns/option-picker.md`).
///
/// Each row shows the option, an optional color swatch, and a checkmark on the current choice. Choosing an option
/// calls `choose` (not for the current one) and dismisses. Rows are at least 44 pt tall and read as selected to
/// VoiceOver (HIG: Pickers, Lists and tables).
public struct OptionPickerSheet: View {
    /// One choice.
    public struct Option: Identifiable, Hashable {
        /// What `choose` receives.
        public var value: String
        /// What the row shows.
        public var label: String
        /// Colors drawn as a gradient swatch; empty for none.
        public var swatch: [Color]

        public var id: String { value }

        /// Creates an option.
        public init(value: String, label: String? = nil, swatch: [Color] = []) {
            self.value = value
            self.label = label ?? value
            self.swatch = swatch
        }
    }

    public var title: String
    public var options: [Option]
    public var selected: String
    public var identifierPrefix: String
    public var choose: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    /// Creates the sheet.
    /// - Parameters:
    ///   - title: The navigation title.
    ///   - options: The choices, in order.
    ///   - selected: The current value.
    ///   - identifierPrefix: Rows get the accessibility identifier `<prefix>.<value>`.
    ///   - choose: Called with a newly chosen value.
    public init(title: String, options: [Option], selected: String, identifierPrefix: String = "option",
                choose: @escaping (String) -> Void) {
        self.title = title
        self.options = options
        self.selected = selected
        self.identifierPrefix = identifierPrefix
        self.choose = choose
    }

    public var body: some View {
        NavigationStack {
            List(options) { option in
                Button {
                    if option.value != selected { choose(option.value) }
                    dismiss()
                } label: {
                    HStack(spacing: HassTokens.Spacing.m) {
                        Text(option.label).foregroundStyle(HassTokens.Ink.primary)
                        Spacer()
                        GradientSwatch(colors: option.swatch)
                        Image(systemName: "checkmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(HassTokens.Ink.action)
                            .opacity(option.value == selected ? 1 : 0)
                            .quickTransition("OptionPickerSheet", value: option.value == selected)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: HassTokens.minTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(option.value == selected ? .isSelected : [])
                .accessibilityIdentifier("\(identifierPrefix).\(option.value)")
            }
            .modalChrome()
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { SheetCloseItem { dismiss() } }
        }
        .tint(HassTokens.Ink.action)
        // The system appearance while the pages behind stay dark (``SystemAppearance``).
        .followsSystemAppearance()
        #if os(iOS)
        // Opaque at every detent: the medium detent's glass let a page's colored tiles show through the rows
        // and fail text contrast (HIG: Sheets; Accessibility, Color and effects).
        .presentationBackground(HassTokens.Surface.systemGround)
        #endif
    }
}

/// Colors as a horizontal gradient capsule; draws nothing for no colors.
public struct GradientSwatch: View {
    public var colors: [Color]

    /// Creates a swatch.
    public init(colors: [Color]) { self.colors = colors }

    public var body: some View {
        if !colors.isEmpty {
            Capsule()
                .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                .frame(width: 44, height: 20)
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.2), lineWidth: 1))
                .accessibilityHidden(true)
        }
    }
}
