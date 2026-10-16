import SwiftUI

/// A section header on a page: 20 pt Bold in primary ink over the tiles and lists on the wallpaper
/// (`.agents/design/direction-g.md`, Type: "Section headers 20 Bold"), with an optional trailing detail in secondary
/// ink ("Page 1 of 5"). At accessibility sizes the detail moves under the title so neither is squeezed. Headers over
/// lists inside a sheet use ``FormHeader`` instead.
public struct PageSectionHeader: View {
    private let title: String
    private let detail: String?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Creates a header.
    /// - Parameters:
    ///   - title: The section's name, in Title Case.
    ///   - detail: Optional trailing text, such as a page or item count.
    public init(_ title: String, detail: String? = nil) {
        self.title = title
        self.detail = detail
    }

    public var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: HassTokens.Spacing.xs))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: HassTokens.Spacing.s))
        layout {
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(HassTokens.Ink.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            if let detail {
                Text(detail)
                    .foregroundStyle(HassTokens.Ink.secondary)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview("Page section header") {
    VStack(alignment: .leading, spacing: 24) {
        PageSectionHeader("Robot Vacuums")
        PageSectionHeader("Suggested Recipes", detail: "Page 1 of 5")
    }
    .padding()
    .background(.black)
}
