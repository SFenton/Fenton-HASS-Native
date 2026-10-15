import HassDesign
import SwiftUI

/// A header over an inset list in the recipe sheets (direction G, Type: "Over inset lists in sheets, 15 Semibold
/// secondary"): ``FilterSection``'s header look in ``FormHeader``'s readable secondary ink, for places that
/// ``FilterSection`` cannot hold (a `Form` section that also needs a footer, and the recipe detail's lists, which sit in
/// a scroll view rather than a `Form`).
struct RecipeSectionHeader: View {
    var title: String
    /// Generated headings ("Section 2", "Other Ingredients") draw in the regular weight, quieter than the recipe's own.
    var isQuiet: Bool

    init(_ title: String, isQuiet: Bool = false) {
        self.title = title
        self.isQuiet = isQuiet
    }

    var body: some View {
        FormHeader(title)
            .font(isQuiet ? .subheadline : .subheadline.weight(.semibold))
            .textCase(nil)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
