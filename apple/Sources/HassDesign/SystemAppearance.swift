import HassTelemetry
import SwiftUI
#if os(iOS)
import UIKit
#endif

/// The split between pages and sheets (`.agents/design/direction-g.md`, Layers; plan decision 6): pages sit on the
/// dimmed house photo, so the signed-in shell forces dark (`preferredColorScheme(.dark)`), and sheets follow the
/// system appearance. The shell cannot read the system appearance from its own environment, because the override
/// answers first, so `RootView` measures the display (``SwiftUICore/View/publishesSystemAppearance()``) and every sheet
/// applies the result to itself (``SwiftUICore/View/followsSystemAppearance()``, done by `hassSheet()` and
/// ``HassModal``).
public enum SystemAppearance {
    /// The launch environment key that pins the sheets' appearance (`light` or `dark`), so journeys render sheets in
    /// light without changing the simulator's setting. `XCUIDevice.shared.appearance` drives the real path.
    public static let overrideKey = "FENTON_APPEARANCE"

    /// The scheme sheets draw in.
    /// - Parameters:
    ///   - override: ``overrideKey``'s value, if any.
    ///   - system: The display's own scheme, or nil when it cannot be read yet.
    /// - Returns: The override when it is `light` or `dark`, else the system scheme, else dark (the shell's own).
    public static func resolve(override: String?, system: ColorScheme?) -> ColorScheme {
        switch override?.lowercased() {
        case "light": .light
        case "dark": .dark
        default: system ?? .dark
        }
    }

    /// ``resolve(override:system:)`` for this process, read now: the launch override and the display's style.
    ///
    /// The display (`UIScreen`) is the source because the window, its scene's views and the shell's environment all carry
    /// the dark override, and because a read costs nothing, so a sheet can ask when it is presented instead of trusting
    /// a value that a missed trait-change callback left stale.
    /// - Parameter fallback: The scheme to use when the display cannot be read.
    @MainActor
    public static func current(fallback: ColorScheme = .dark) -> ColorScheme {
        resolve(override: overrideValue, system: liveSystemScheme() ?? fallback)
    }

    /// The display's own scheme, or nil without a window scene (previews, `swift test`).
    @MainActor
    static func liveSystemScheme() -> ColorScheme? {
        #if os(iOS)
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return scene.map { scheme(of: $0.screen.traitCollection) }
        #else
        return nil
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
    /// What the shell last published. Read so the sheet re-evaluates when it changes; the display is asked again each
    /// time, so a sheet presented after a change is right even before the callback arrives.
    @Environment(\.systemColorScheme) private var published

    func body(content: Content) -> some View {
        content.preferredColorScheme(SystemAppearance.current(fallback: published))
    }
}

#if os(iOS)
/// An invisible view that reports the user's interface style, which `preferredColorScheme` does not touch: the display's
/// (`UIScreen`) rather than the window's or a view's, which carry the shell's dark override. It reads again when the
/// scene's traits change and when the app becomes active, so a change made in Control Center reaches the sheets.
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
        // Read in `deinit`, which is nonisolated; only the main thread writes it.
        nonisolated(unsafe) private var activation: (any NSObjectProtocol)?
        private var census: ResourceCensus.Registration?

        override init(frame: CGRect) {
            super.init(frame: frame)
            census = ResourceCensus.shared.register { [weak self] in ["Appearance.activationObservers": self?.activation == nil ? 0 : 1] }
        }

        required init?(coder: NSCoder) { nil }

        deinit {
            if let activation { NotificationCenter.default.removeObserver(activation) }
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            registration = nil
            // A block observer stays registered until removed; dropping the token alone would add one per move.
            if let activation { NotificationCenter.default.removeObserver(activation) }
            activation = nil
            guard let scene = window?.windowScene else { return }
            report()
            registration = scene.registerForTraitChanges([UITraitUserInterfaceStyle.self]) { [weak self] (_: UIWindowScene, _) in
                self?.report()
            }
            activation = NotificationCenter.default.addObserver(
                forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.report() }
            }
        }

        private func report() {
            guard let window else { return }
            let system = SystemAppearance.scheme(of: window.screen.traitCollection)
            onChange(SystemAppearance.resolve(override: SystemAppearance.overrideValue, system: system))
            #if DEBUG
            // `FENTON_APPEARANCE_DEBUG=1` exposes what each source says, for a journey that checks the system path.
            if ProcessInfo.processInfo.environment["FENTON_APPEARANCE_DEBUG"] == "1" {
                isAccessibilityElement = true
                accessibilityIdentifier = "appearance.probe"
                accessibilityLabel = "screen=\(window.screen.traitCollection.userInterfaceStyle.rawValue) "
                    + "scene=\(window.windowScene?.traitCollection.userInterfaceStyle.rawValue ?? -1) "
                    + "window=\(window.traitCollection.userInterfaceStyle.rawValue)"
            }
            #endif
        }
    }
}
#endif
