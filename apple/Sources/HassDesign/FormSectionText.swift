import SwiftUI

// MARK: - Form section text

/// A `Form` section header in ``HassTokens/Ink/secondary``. The system draws plain section headers and footers in its
/// secondary label color, which measured about 3.3:1 on the grouped background behind every sheet (Inventory Add
/// Item, sign-in, Chores forms; WCAG 1.4.3). Use `Section { … } header: { FormHeader("…") }` instead of
/// `Section("…")`; the system keeps the header's font and case.
public struct FormHeader: View {
    public var title: String

    /// Creates a header.
    public init(_ title: String) { self.title = title }

    public var body: some View {
        Text(title)
            .foregroundStyle(HassTokens.Ink.secondary)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A `Form` section footer in ``HassTokens/Ink/secondary`` (see ``FormHeader`` for why).
public struct FormFooter: View {
    public var text: String

    /// Creates a footer.
    public init(_ text: String) { self.text = text }

    public var body: some View {
        Text(text).foregroundStyle(HassTokens.Ink.secondary)
    }
}
