import HassCore
import HassDesign
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Explains location reporting and walks through the permission steps (`.agents/pages/settings/location.md`):
/// not asked → While Using → Always, with Settings as the way back from Off or Approximate.
///
/// HIG: [Privacy](https://developer.apple.com/design/human-interface-guidelines/privacy) (pre-alert screens: one
/// button titled "Continue", no other way out) and [Sheets](https://developer.apple.com/design/human-interface-guidelines/sheets).
/// The asking stages drop Direction G's Close and can't be swiped away, because HIG's pre-alert rule wins over the
/// modal pattern; the status stages (Always, Off, Approximate) keep Close.
public struct LocationPermissionView: View {
    private let permission: LocationPermission
    private let onRequestPermission: () -> Void
    private let onOpenSettings: (() -> Void)?
    private let onClose: () -> Void

    @Environment(\.openURL) private var openURL
    @ScaledMetric(relativeTo: .largeTitle) private var symbolSize: CGFloat = 56

    /// Creates the screen.
    /// - Parameters:
    ///   - permission: The current permission; the screen follows it as it changes.
    ///   - onRequestPermission: Shows the next system alert (``LocationReporter/requestPermission()``).
    ///   - onOpenSettings: Opens Settings; nil opens the app's Settings page.
    ///   - onClose: Dismisses the screen.
    public init(permission: LocationPermission, onRequestPermission: @escaping () -> Void,
                onOpenSettings: (() -> Void)? = nil, onClose: @escaping () -> Void) {
        self.permission = permission
        self.onRequestPermission = onRequestPermission
        self.onOpenSettings = onOpenSettings
        self.onClose = onClose
    }

    private var copy: LocationPermissionCopy { LocationPermissionCopy(stage: permission.stage) }

    public var body: some View {
        NavigationStack {
            ScrollView {
                content
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
            }
            .modalChrome()
            .navigationTitle("Location")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                if !copy.isPreAlert {
                    SheetCloseItem(identifier: "location.close", action: onClose)
                }
            }
            .safeAreaInset(edge: .bottom) { actionBar }
        }
        .interactiveDismissDisabled(copy.isPreAlert)
    }

    // MARK: - Content

    private var content: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.xl) {
            VStack(alignment: .leading, spacing: HassTokens.Spacing.m) {
                Image(systemName: symbol)
                    .font(.system(size: symbolSize))
                    .foregroundStyle(symbolColor)
                    .accessibilityHidden(true)
                Text(copy.title)
                    .font(.title2.bold())
                    .foregroundStyle(HassTokens.Ink.primary)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("location.title")
                Text(copy.message)
                    .font(.body)
                    .foregroundStyle(HassTokens.Ink.secondary)
                    .accessibilityIdentifier("location.message")
            }
            .fixedSize(horizontal: false, vertical: true)

            LocationStatusRow(permission: permission)

            if copy.showsPoints {
                VStack(alignment: .leading, spacing: HassTokens.Spacing.l) {
                    ForEach(LocationPermissionCopy.points) { point in
                        LocationPointRow(point: point)
                    }
                }
            }

            if let footnote = copy.footnote {
                Text(footnote)
                    .font(.footnote)
                    .foregroundStyle(HassTokens.Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("location.footnote")
            }
        }
        .padding(.horizontal, HassTokens.Spacing.xl)
        .padding(.vertical, HassTokens.Spacing.l)
    }

    @ViewBuilder
    private var actionBar: some View {
        if let title = copy.actionTitle {
            PrimaryButton(title) { perform(copy.action) }
                .accessibilityIdentifier("location.primary")
                .padding(.horizontal, HassTokens.Spacing.xl)
                .padding(.vertical, HassTokens.Spacing.m)
                .frame(maxWidth: 560)
        }
    }

    func perform(_ action: LocationPermissionCopy.Action?) {
        switch action {
        case .requestPermission: onRequestPermission()
        case .openSettings: openSettings()
        case nil: break
        }
    }

    private func openSettings() {
        if let onOpenSettings { return onOpenSettings() }
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        #endif
    }

    // MARK: - Style

    private var symbol: String {
        switch permission.stage {
        case .notDetermined, .whenInUse: "location.circle.fill"
        case .always: "location.fill"
        case .denied: "location.slash.fill"
        case .reducedAccuracy: "scope"
        }
    }

    private var symbolColor: Color {
        switch permission.stage {
        case .denied: HassTokens.Ink.danger
        case .reducedAccuracy: HassTokens.Ink.warning
        case .notDetermined, .whenInUse, .always: HassTokens.Ink.action
        }
    }

    /// The inset cell colour on the grouped sheet background.
    static var cellColor: Color {
        #if canImport(UIKit)
        Color(uiColor: .secondarySystemGroupedBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }
}

#Preview("Location permission") {
    LocationPermissionView(permission: .notDetermined, onRequestPermission: {}, onClose: {})
}
