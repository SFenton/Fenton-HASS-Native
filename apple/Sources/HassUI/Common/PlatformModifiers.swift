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

    /// Hides the content from assistive technologies only while `hidden` is true, without un-hiding
    /// descendants (FestivalNativeApps `accessibilityHidden(while:)`). `.accessibilityHidden(someBool)`
    /// did not reach the pages of the UIKit-backed root `TabView`.
    func accessibilityHidden(while hidden: Bool) -> some View {
        modifier(AccessibilityHiddenWhile(hidden: hidden))
    }
}

/// Implementation of ``SwiftUI/View/accessibilityHidden(while:)``.
private struct AccessibilityHiddenWhile: ViewModifier {
    var hidden: Bool

    func body(content: Content) -> some View {
        if #available(iOS 18.0, macOS 15.0, *) {
            content.accessibilityHidden(true, isEnabled: hidden)
        } else {
            content.accessibilityHidden(hidden)
        }
    }
}
