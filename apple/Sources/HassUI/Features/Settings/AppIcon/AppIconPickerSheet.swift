import HassCore
import HassDesign
import SwiftUI

/// Settings → App Icon: the eight icons in a grid with their names, the installed one checked. Choosing one installs it
/// (``AppIconPickerModel/select(_:)``); iOS shows its own notice when the icon changes.
///
/// Content-fitted (`hassSheet(.form)`: a list of choices, so a form sheet on iPad). The grid's column count follows the
/// text size: two columns on iPhone and three on a form sheet, one at accessibility sizes where the icon grows with the text.
/// HIG App icons: "Alternate icons: ... may let people choose a related icon in settings"; HIG Sheets for the container.
struct AppIconPickerSheet: View {
    @Bindable var model: AppIconPickerModel
    @ScaledMetric(relativeTo: .body) private var cellMinimum: CGFloat = 130

    var body: some View {
        HassModal("App Icon", closeIdentifier: "appIcon.close") {
            ScrollView {
                VStack(alignment: .leading, spacing: HassTokens.Spacing.l) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: cellMinimum), spacing: HassTokens.Spacing.l, alignment: .top)],
                              spacing: HassTokens.Spacing.xl) {
                        ForEach(AppIconChoice.allCases) { choice in
                            AppIconChoiceButton(choice: choice, isSelected: model.isSelected(choice)) {
                                Task { await model.select(choice) }
                            }
                            .disabled(model.isChanging)
                        }
                    }
                    Text("iOS shows its own notice when the icon changes. Every icon also has dark and tinted Home Screen versions.")
                        .font(.footnote)
                        .foregroundStyle(HassTokens.Surface.secondaryInSheet)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("appIcon.footer")
                }
                .padding(.horizontal, HassTokens.Spacing.l)
                .padding(.top, HassTokens.Spacing.s)
                .padding(.bottom, HassTokens.Spacing.l)
            }
        }
        .accessibilityIdentifier("appIcon.sheet")
        .alert("Couldn't Change Icon", isPresented: $model.isShowingFailure) {
            Button("OK", role: .cancel) { model.failureMessage = nil }
                .accessibilityIdentifier("appIcon.failure.ok")
        } message: {
            Text(model.failureMessage ?? "")
        }
    }
}
