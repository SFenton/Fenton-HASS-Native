import HassCore
import HassDesign
import SwiftUI

/// Low-opacity scene decoration drawn in a `Canvas`.
struct WeatherDecoration: View {
    var scene: WeatherScene
    var animated: Bool
    @Environment(\.scenePhase) private var scenePhase

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

    /// Falling streaks (rain) or flakes (snow); a still frame when motion is reduced. The timeline stops while the app is
    /// not active (nothing is on screen to animate), and every streak is one stroke of one path: they share a colour and a
    /// width, and thirty-six separate strokes a frame at 24 fps were most of the sheet's idle CPU
    /// (`.agents/testing/apple/performance.md`).
    private func streaks(count: Int, slant: Double, length: Double, opacity: Double) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !animated || scenePhase != .active)) { timeline in
            let phase = animated ? timeline.date.timeIntervalSinceReferenceDate : 0
            Canvas { context, size in
                var path = Path()
                for index in 0..<count {
                    let seed = Double(index) * 0.618033988
                    let x = (seed.truncatingRemainder(dividingBy: 1)) * size.width
                    let speed = 0.12 + (Double(index % 5) * 0.03)
                    let progress = ((phase * speed) + seed * 3).truncatingRemainder(dividingBy: 1)
                    let y = progress * (size.height + length) - length
                    path.move(to: CGPoint(x: x, y: y))
                    path.addLine(to: CGPoint(x: x + length * slant, y: y + length))
                }
                context.stroke(path, with: .color(.white.opacity(opacity)), lineWidth: length > 10 ? 1 : 2.5)
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
