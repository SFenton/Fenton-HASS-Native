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

/// Low-opacity scene decoration drawn in a `Canvas`.
private struct WeatherDecoration: View {
    var scene: WeatherScene
    var animated: Bool

    var body: some View {
        switch scene {
        case .night:
            Canvas { context, size in
                for star in Self.stars {
                    let rect = CGRect(x: star.x * size.width, y: star.y * size.height * 0.7, width: star.size, height: star.size)
                    context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(star.opacity)))
                }
            }
        case .clouds, .fog, .wind, .neutral, .exceptional:
            Canvas { context, size in
                for (index, bank) in Self.banks.enumerated() {
                    let rect = CGRect(x: bank.x * size.width, y: bank.y * size.height, width: size.width * bank.width, height: size.height * 0.16)
                    context.fill(Path(roundedRect: rect, cornerRadius: rect.height / 2), with: .color(.white.opacity(scene == .fog ? 0.07 : 0.045 + Double(index % 2) * 0.015)))
                }
            }
        case .rain, .storm:
            streaks(count: 36, slant: 0.18, length: 26, opacity: 0.16)
        case .snow:
            streaks(count: 30, slant: 0.04, length: 5, opacity: 0.30)
        case .sunny:
            Canvas { context, size in
                let glow = Path(ellipseIn: CGRect(x: size.width * 0.55, y: -size.height * 0.12, width: size.width * 0.9, height: size.width * 0.9))
                context.fill(glow, with: .radialGradient(Gradient(colors: [.white.opacity(0.16), .clear]), center: CGPoint(x: size.width * 1.0, y: 0), startRadius: 0, endRadius: size.width * 0.5))
            }
        }
    }

    /// Falling streaks (rain) or flakes (snow); a still frame when motion is reduced.
    private func streaks(count: Int, slant: Double, length: Double, opacity: Double) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !animated)) { timeline in
            let phase = animated ? timeline.date.timeIntervalSinceReferenceDate : 0
            Canvas { context, size in
                for index in 0..<count {
                    let seed = Double(index) * 0.618033988
                    let x = (seed.truncatingRemainder(dividingBy: 1)) * size.width
                    let speed = 0.12 + (Double(index % 5) * 0.03)
                    let progress = ((phase * speed) + seed * 3).truncatingRemainder(dividingBy: 1)
                    let y = progress * (size.height + length) - length
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: y))
                    path.addLine(to: CGPoint(x: x + length * slant, y: y + length))
                    context.stroke(path, with: .color(.white.opacity(opacity)), lineWidth: length > 10 ? 1 : 2.5)
                }
            }
        }
    }

    private struct Star { var x: Double; var y: Double; var size: Double; var opacity: Double }

    private static let stars: [Star] = (0..<34).map { index in
        let x = (Double(index) * 0.6180339887).truncatingRemainder(dividingBy: 1)
        let y = (Double(index) * 0.3247179572 + 0.17).truncatingRemainder(dividingBy: 1)
        return Star(x: x, y: y, size: index % 7 == 0 ? 2.4 : index % 3 == 0 ? 1.8 : 1.2, opacity: index % 7 == 0 ? 0.5 : 0.24 + Double(index % 4) * 0.04)
    }

    private static let banks: [(x: Double, y: Double, width: Double)] = [
        (-0.1, 0.08, 0.7), (0.4, 0.22, 0.8), (-0.05, 0.42, 0.65), (0.5, 0.6, 0.7), (0.0, 0.78, 0.75),
    ]
}
