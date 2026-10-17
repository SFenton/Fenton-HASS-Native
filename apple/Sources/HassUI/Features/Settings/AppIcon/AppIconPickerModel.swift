import HassCore
import Observation

/// The state behind Settings → App Icon: which icon is installed and the change in flight.
///
/// The row and the sheet share one model, so the row's preview follows a choice made in the sheet. The system calls
/// are injected (``AppIconPlatform``), so tests drive it without `UIApplication`.
@MainActor @Observable
final class AppIconPickerModel {
    private let platform: AppIconPlatform

    /// The icon that is installed, read back from the system after every change.
    private(set) var selected: AppIconChoice
    /// Whether a change is waiting on the system; taps are ignored meanwhile.
    private(set) var isChanging = false
    /// The text of the error alert after a change the system refused, nil when there is none.
    var failureMessage: String?

    /// Whether the error alert is up; the alert clears it by setting this false.
    var isShowingFailure: Bool {
        get { failureMessage != nil }
        set { if !newValue { failureMessage = nil } }
    }

    /// Creates the model over the installed icon.
    init(platform: AppIconPlatform) {
        self.platform = platform
        isSupported = platform.supportsAlternateIcons()
        selected = AppIconChoice(alternateIconName: platform.currentName())
    }

    /// Whether the app can switch icons on this device, read once with the installed icon.
    let isSupported: Bool

    /// Whether `choice` is the installed icon.
    func isSelected(_ choice: AppIconChoice) -> Bool { choice == selected }

    /// Installs `choice`. iOS shows its own notice when the icon changes; a refusal raises ``failureMessage`` and leaves
    /// the selection where it was.
    func select(_ choice: AppIconChoice) async {
        guard !isChanging, choice != selected else { return }
        isChanging = true
        defer { isChanging = false }
        do {
            try await platform.setName(choice.alternateIconName)
            selected = AppIconChoice(alternateIconName: platform.currentName())
        } catch {
            failureMessage = Self.failureText(for: choice, error: error)
        }
    }

    /// The alert's message: the choice that failed and the system's reason.
    static func failureText(for choice: AppIconChoice, error: any Error) -> String {
        "The icon wasn't changed to \(choice.displayName). \(error.localizedDescription)"
    }
}
