import SwiftUI
#if os(iOS)
import UIKit
#endif

/// The split between pages and sheets (`.agents/design/direction-g.md`, Layers; plan decision 6): pages sit on the
/// dimmed house photo, so the signed-in shell forces dark (`preferredColorScheme(.dark)`), and sheets follow the
/// system appearance. The shell cannot read the system appearance from its own environment, because the override
/// answers first, so it measures the window scene (``SwiftUICore/View/publishesSystemAppearance()``) and every sheet
/// applies the result to itself (``SwiftUICore/View/followsSystemAppearance()``, done by `hassSheet()` and
/// ``HassModal``).
public enum SystemAppearance {
    /// The launch environment key that pins the sheets' appearance (`light` or `dark`), so journeys render sheets in
    /// light without changing the simulator's setting. `XCUIDevice.shared.appearance` drives the real path.
    public static let overrideKey = "FENTON_APPEARANCE"

    /// The scheme sheets draw in.
    /// - Parameters:
    ///   - override: ``overrideKey``'s value, if any.
    ///   - system: The window scene's own scheme, or nil when it cannot be read yet.
    /// - Returns: The override when it is `light` or `dark`, else the system scheme, else dark (the shell's own).
    public static func resolve(override: String?, system: ColorScheme?) -> ColorScheme {
        switch override?.lowercased() {
        case "light": .light
        case "dark": .dark
        default: system ?? .dark
        }
    }

    /// ``resolve(override:system:)`` for this process: the launch override and the first window scene.
    @MainActor
    public static func current() -> ColorScheme {
        #if os(iOS)
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        return resolve(override: overrideValue, system: scene.map { scheme(of: $0.traitCollection) })
        #else
        return resolve(override: overrideValue, system: nil)
        #endif
    }

    fileprivate static var overrideValue: String? {
        #if DEBUG
        ProcessInfo.processInfo.environment[overrideKey]
        #else
        nil
        #endif
    }

    #if os(iOS)
    fileprivate static func scheme(of traits: UITraitCollection) -> ColorScheme {
        traits.userInterfaceStyle == .light ? .light : .dark
    }
    #endif
}

public extension EnvironmentValues {
    /// The appearance sheets draw in: the user's system appearance, which the shell's dark override hides from its own
    /// `colorScheme`. Dark until a shell publishes it (previews, `swift test`).
    @Entry var systemColorScheme: ColorScheme = .dark
}

public extension View {
    /// Publishes the system appearance to every sheet below (the signed-in shell and each gallery root, next to their
    /// `preferredColorScheme(.dark)`).
    func publishesSystemAppearance() -> some View {
        modifier(PublishSystemAppearance())
    }

    /// Draws this presentation in the system appearance, even under a shell that forces dark. `hassSheet()` and
    /// ``HassModal`` apply it; apply it directly to a sheet that uses neither. A sheet that is dark by design
    /// (Weather, Login, the camera viewer) sets `preferredColorScheme(.dark)` instead and never calls this.
    func followsSystemAppearance() -> some View {
        modifier(FollowSystemAppearance())
    }
}

private struct PublishSystemAppearance: ViewModifier {
    @State private var scheme: ColorScheme = SystemAppearance.current()

    func body(content: Content) -> some View {
        content
            .environment(\.systemColorScheme, scheme)
            #if os(iOS)
            .background { SceneAppearanceProbe(scheme: $scheme) }
            #endif
    }
}

private struct FollowSystemAppearance: ViewModifier {
    @Environment(\.systemColorScheme) private var scheme

    func body(content: Content) -> some View {
        content.preferredColorScheme(scheme)
    }
}

#if os(iOS)
/// An invisible view that reports the window scene's interface style, which `preferredColorScheme` does not touch,
/// now and whenever the user changes the appearance.
private struct SceneAppearanceProbe: UIViewRepresentable {
    @Binding var scheme: ColorScheme

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        view.onChange = { scheme = $0 }
        return view
    }

    func updateUIView(_ view: ProbeView, context: Context) {
        view.onChange = { scheme = $0 }
    }

    final class ProbeView: UIView {
        var onChange: (ColorScheme) -> Void = { _ in }
        private var registration: (any UITraitChangeRegistration)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            registration = nil
            guard let scene = window?.windowScene else { return }
            report(scene.traitCollection)
            registration = scene.registerForTraitChanges([UITraitUserInterfaceStyle.self]) { [weak self] (scene: UIWindowScene, _) in
                self?.report(scene.traitCollection)
            }
        }

        private func report(_ traits: UITraitCollection) {
            onChange(SystemAppearance.resolve(override: SystemAppearance.overrideValue,
                                              system: SystemAppearance.scheme(of: traits)))
        }
    }
}
#endif
