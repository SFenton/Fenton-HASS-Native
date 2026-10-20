import HassCore
import HassDesign
import SwiftUI

/// The Summary sheet's Profile-tab Location section (`.agents/pages/settings/location.md`, Entry points): Share Location with the
/// permission state, which opens ``LocationPermissionView``, and why this iPhone isn't on its person yet, if it isn't.
///
/// Phones only: ``YourSummarySheet``'s Profile tab shows it when the session has a ``LocationCoordinator``, which an iPad never has.
/// HIG: [Toggles](https://developer.apple.com/design/human-interface-guidelines/toggles) (there is no switch: reporting
/// follows the permission) and [Privacy](https://developer.apple.com/design/human-interface-guidelines/privacy)
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
        } header: {
            FormHeader("Location")
        } footer: {
            // The warning sits under the card, above what reporting does, so the card keeps its corners.
            VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
                if let warning = Self.warning(stage: permission.stage) {
                    InlineAlert(warning)
                        .accessibilityIdentifier("account.location.warning")
                }
                if let link = Self.linkNotice(location.mobileAppPresenceLink) {
                    InlineAlert(link)
                        .accessibilityIdentifier("account.location.link")
                }
                FormFooter(Self.footer)
            }
        }
    }

    /// What reporting does, under the row.
    static let footer = "Whenever location access is on, this iPhone reports to Home Assistant as its own device, "
        + "and Home Assistant follows it for the person you sign in as."

    /// Why nothing is sent; nil while location can be reported.
    /// - Parameter stage: The permission's stage.
    static func warning(stage: LocationPermission.Stage) -> String? {
        switch stage {
        case .notDetermined: "Location access isn't set, so nothing is sent. Open Share Location to allow it."
        case .denied: "Location access is off, so nothing is sent. Open Share Location to turn it on in Settings."
        case .reducedAccuracy: "Precise Location is off, so Home Assistant can't tell whether you're home."
        case .whenInUse, .always: nil
        }
    }

    /// Why this iPhone isn't on its person yet; nil when it is, or before the first attempt.
    /// - Parameter outcome: What the last link attempt did.
    static func linkNotice(_ outcome: PresenceLinkOutcome?) -> String? {
        switch outcome {
        case .needsAdmin: "Home Assistant lets only administrators add this iPhone to a person. Ask an administrator to add it to yours."
        case .noPerson: "No person in Home Assistant uses your account yet, so it can't follow this iPhone. Ask an administrator to add one."
        case .trackerMissing: "Home Assistant hasn't created this iPhone's device yet. It will try again at the next sign-in."
        case .failed: "Couldn't add this iPhone to your person. It will try again at the next connection."
        case .linked, .alreadyLinked, nil: nil
        }
    }
}
