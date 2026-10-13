import HassDesign
import SwiftUI

/// A box's name with a visible line explaining what to write. HIG (Text fields): placeholder text
/// "disappears on typing, so a separate label can also help".
struct FeedbackFieldHeader: View {
    let title: String
    let detail: String

    init(_ title: String, detail: String) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HassTokens.Ink.primary)
                .accessibilityAddTraits(.isHeader)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(HassTokens.Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .textCase(nil)
        .accessibilityElement(children: .combine)
    }
}
