import HassCore
import HassDesign
import SwiftUI

/// The Summary sheet's Profile-tab Location section (`.agents/pages/settings/location.md`, Entry points): Share Location with the
/// permission state, which opens ``LocationPermissionView``, and the toggle that arms reporting on this install.
///
/// Phones only: ``YourSummarySheet``'s Profile tab shows it when the session has a ``LocationCoordinator``, which an iPad never has.
/// HIG: [Toggles](https://developer.apple.com/design/human-interface-guidelines/toggles) (a switch in a list row for
/// an on/off setting, its effect in the footer) and [Privacy](https://developer.apple.com/design/human-interface-guidelines/privacy)
/// (the permission screen, not the system alert, is the way in).
struct LocationAccountSection: View {
    @Bindable var location: LocationCoordinator
    /// Set by Share Location; the Account sheet presents the permission screen from its list, since a sheet attached
    /// to a section inside a `List` didn't present on the folded iPhone Duo (2026-10-15).
    @Binding var showsPermission: Bool

    private var permission: LocationPermission { location.reporter.permission }
    private var status: String { LocationPermissionCopy.status(permission) }

    var body: some View {
        Section {
            Button { showsPermission = true } label: {
                HStack(spacing: HassTokens.Spacing.m) {
                    LabeledContent {
                        Text(status).foregroundStyle(HassTokens.Ink.secondary)
                    } label: {
                        Label("Share Location", systemImage: "location.fill")
                            .foregroundStyle(HassTokens.Ink.primary)
                    }
                    Image(systemName: "chevron.forward")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: HassTokens.minTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Share Location")
            .accessibilityValue(status)
            .accessibilityHint("Shows location access for this iPhone.")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("account.location")

            Toggle(isOn: $location.armsReporting) {
                Text("Report to Home Assistant").foregroundStyle(HassTokens.Ink.primary)
            }
            .frame(minHeight: HassTokens.minTarget)
            .accessibilityIdentifier("account.location.report")
        } header: {
            FormHeader("Location")
        } footer: {
            // The warning sits under the card, above what the toggle does, so the card keeps its corners.
            VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
                if let warning = Self.warning(armed: location.isReportingArmed, stage: permission.stage) {
                    InlineAlert(warning)
                        .accessibilityIdentifier("account.location.warning")
                }
                FormFooter(Self.footer)
            }
        }
    }

    /// What reporting does, under the toggle.
    static let footer = "Sends this iPhone's location to Home Assistant as its own device. Who's home changes only "
        + "when that device is added to a person."

    /// Why an armed toggle sends nothing; nil while it can send, or while it is off.
    /// - Parameters:
    ///   - armed: The toggle is on.
    ///   - stage: The permission's stage.
    static func warning(armed: Bool, stage: LocationPermission.Stage) -> String? {
        guard armed else { return nil }
        return switch stage {
        case .notDetermined: "Location access isn't set, so nothing is sent. Open Share Location to allow it."
        case .denied: "Location access is off, so nothing is sent. Open Share Location to turn it on in Settings."
        case .reducedAccuracy: "Precise Location is off, so Home Assistant can't tell whether you're home."
        case .whenInUse, .always: nil
        }
    }
}
