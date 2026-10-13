import HassCore
import HassDesign
import SwiftUI

/// The wind compass: 48 ticks, a north marker, cardinal letters and, when the wind has a direction, an arrow that
/// points where the wind blows to with a dot at the side it comes from (web `WindCompass`).
///
/// Decorative: the tile speaks speed, gust and direction. The needle turns the short way round and does not animate
/// when Reduce Motion is on.
struct WeatherCompass: View {
    /// Where the wind comes from, in degrees; `nil` for calm or unknown.
    var sourceDegrees: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var angle: Double?

    var body: some View {
        ZStack {
            Canvas { context, size in
                let radius = min(size.width, size.height) / 2
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                for index in 0..<48 {
                    let long = index % 2 == 0
                    let theta = Double(index) * (.pi * 2 / 48) - .pi / 2
                    var path = Path()
                    path.move(to: CGPoint(x: center.x + cos(theta) * radius * 0.92, y: center.y + sin(theta) * radius * 0.92))
                    path.addLine(to: CGPoint(x: center.x + cos(theta) * radius * (long ? 0.80 : 0.85), y: center.y + sin(theta) * radius * (long ? 0.80 : 0.85)))
                    context.stroke(path, with: .color(.white.opacity(index == 0 ? 0 : 0.55)), lineWidth: 1.2)
                }
                var north = Path()
                north.move(to: CGPoint(x: center.x, y: center.y - radius * 0.94))
                north.addLine(to: CGPoint(x: center.x + radius * 0.06, y: center.y - radius * 0.84))
                north.addLine(to: CGPoint(x: center.x - radius * 0.06, y: center.y - radius * 0.84))
                north.closeSubpath()
                context.fill(north, with: .color(.white))
            }
            letter("N", x: 0, y: -0.58)
            if sourceDegrees != nil {
                letter("E", x: 0.58, y: 0)
                letter("W", x: -0.58, y: 0)
            }
            letter("S", x: 0, y: 0.58)
            if let angle {
                WindNeedle()
                    .rotationEffect(.degrees(angle))
                    .animation(reduceMotion ? nil : .smooth(duration: Double(WeatherPresentation.dataTransitionMs) / 1000), value: angle)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .onAppear { angle = sourceDegrees }
        .onChange(of: sourceDegrees) { _, new in
            guard let new else {
                angle = nil
                return
            }
            // Unwrap so a 350 to 10 change turns 20 degrees, not 340.
            let from = angle ?? new
            angle = from + WeatherPresentation.shortestBearingDelta(from: from, to: new)
        }
        .accessibilityHidden(true)
    }

    private func letter(_ text: String, x: Double, y: Double) -> some View {
        GeometryReader { proxy in
            let radius = min(proxy.size.width, proxy.size.height) / 2
            Text(text)
                .font(.system(size: max(10, radius * 0.2), weight: .semibold, design: .rounded))
                .foregroundStyle(HassTokens.Ink.onDark)
                .position(x: proxy.size.width / 2 + radius * x, y: proxy.size.height / 2 + radius * y)
        }
    }
}
