import SwiftUI

// MARK: - Cross-platform shims

/// iOS-only modifiers wrapped so HassUI also builds on macOS, where `swift test` hosts the UI tests
/// (FestivalNativeApps' hosted-test model; `.agents/testing/apple/README.md`).
extension View {
    /// A URL entry field: URL keyboard, no autocapitalization or autocorrection.
    func urlEntryField() -> some View {
        #if os(iOS)
        textContentType(.URL)
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        #else
        autocorrectionDisabled()
        #endif
    }

    /// A username field.
    func usernameEntryField() -> some View {
        #if os(iOS)
        textContentType(.username)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        #else
        textContentType(.username).autocorrectionDisabled()
        #endif
    }

    /// A one-time-code field.
    func oneTimeCodeEntryField() -> some View {
        #if os(iOS)
        textContentType(.oneTimeCode).keyboardType(.numberPad)
        #else
        textContentType(.oneTimeCode)
        #endif
    }

    /// Inline navigation title on iOS; no-op on macOS.
    func inlineNavigationTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}
