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

/// One icon in the grid: its art, its name, "Default" under the app's own icon and a check on the installed one.
///
/// A button named "Navy and Sky" (", default" for the default) whose value is "Selected" or "Not selected": the check
/// and the ring are not the only signal (HIG Accessibility: do not rely on colour alone).
struct AppIconChoiceButton: View {
    let choice: AppIconChoice
    let isSelected: Bool
    let action: () -> Void

    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 88
    private static let ringGap: CGFloat = 5

    var body: some View {
        Button(action: action) {
            VStack(spacing: HassTokens.Spacing.s) {
                AppIconPreview(choice: choice, side: side)
                    .padding(Self.ringGap)
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: side * AppIconPreview.cornerFraction + Self.ringGap, style: .continuous)
                                .strokeBorder(HassTokens.Ink.action, lineWidth: 3)
                        }
                    }
                HStack(spacing: HassTokens.Spacing.xs) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(HassTokens.Ink.action)
                    }
                    Text(choice.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(HassTokens.Ink.primary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if choice.isDefault {
                    Text("Default")
                        .font(.caption)
                        .foregroundStyle(HassTokens.Surface.secondaryInSheet)
                }
            }
            .frame(maxWidth: .infinity, minHeight: HassTokens.minTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(choice.isDefault ? "\(choice.spokenName), default" : choice.spokenName)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityIdentifier("appIcon.choice.\(choice.rawValue)")
    }
}
