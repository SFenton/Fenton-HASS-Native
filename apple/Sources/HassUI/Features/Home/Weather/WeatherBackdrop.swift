import HassCore
import HassDesign
import SwiftUI

/// The condition-aware gradient behind the weather card and sheet (web `WeatherAtmosphere`).
///
/// Every scene is dark enough for white text at 4.5:1 or better (the lightest stop is at least 5.6:1), so text keeps
/// its contrast whatever the condition. Decoration (stars, cloud banks, rain, snow) is drawn at low opacity and only
/// animates when Reduce Motion is off; with Reduce Transparency on, it is left out and the gradient stays solid.
/// HIG: Color (contrast), Motion, Accessibility (Reduce Motion, Reduce Transparency).
struct WeatherBackdrop: View {
    var scene: WeatherScene
    /// Whether to draw the decoration. The card leaves it out for a calmer surface.
    var decorated = true
    /// Treat Reduce Motion / Reduce Transparency as on regardless of the system setting (tests; the environment
    /// values are read-only, so a hosted test cannot set them).
    var forceReduceMotion = false
    var forceReduceTransparency = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency

    private var reduceMotion: Bool { forceReduceMotion || systemReduceMotion }
    private var reduceTransparency: Bool { forceReduceTransparency || systemReduceTransparency }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Self.colors(for: scene).top, Self.colors(for: scene).bottom], startPoint: .top, endPoint: .bottom)
            if decorated, !reduceTransparency {
                WeatherDecoration(scene: scene, animated: !reduceMotion)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityHidden(true)
    }

    /// Top and bottom gradient stops for a scene.
    static func colors(for scene: WeatherScene) -> (top: Color, bottom: Color) {
        switch scene {
        case .sunny: (Color(red: 0.13, green: 0.40, blue: 0.78), Color(red: 0.05, green: 0.17, blue: 0.40))
        case .night: (Color(red: 0.07, green: 0.09, blue: 0.27), Color(red: 0.02, green: 0.03, blue: 0.10))
        case .clouds: (Color(red: 0.28, green: 0.36, blue: 0.46), Color(red: 0.11, green: 0.15, blue: 0.22))
        case .fog: (Color(red: 0.34, green: 0.39, blue: 0.44), Color(red: 0.15, green: 0.18, blue: 0.22))
        case .rain: (Color(red: 0.20, green: 0.28, blue: 0.40), Color(red: 0.07, green: 0.11, blue: 0.19))
        case .storm: (Color(red: 0.19, green: 0.16, blue: 0.33), Color(red: 0.06, green: 0.05, blue: 0.13))
        case .snow: (Color(red: 0.30, green: 0.40, blue: 0.52), Color(red: 0.12, green: 0.18, blue: 0.28))
        case .wind: (Color(red: 0.14, green: 0.40, blue: 0.46), Color(red: 0.05, green: 0.16, blue: 0.20))
        case .exceptional: (Color(red: 0.45, green: 0.25, blue: 0.12), Color(red: 0.17, green: 0.09, blue: 0.05))
        case .neutral: (Color(red: 0.22, green: 0.30, blue: 0.42), Color(red: 0.08, green: 0.11, blue: 0.18))
        }
    }
}
