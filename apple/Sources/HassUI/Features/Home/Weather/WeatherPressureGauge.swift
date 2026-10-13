import HassCore
import HassDesign
import SwiftUI

/// The barometer: 49 ticks over a 250 degree arc from 970 to 1050 hPa with the current reading's tick lit (web
/// `pressureGauge*`). The value and unit are real text centered in the dial so they scale with Dynamic Type.
struct WeatherPressureGauge: View {
    /// 0...100 across the gauge.
    var percent: Double
    var value: String
    var unit: String?

    var body: some View {
        ZStack {
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height * 0.56)
                let radius = min(size.width, size.height * 1.4) / 2
                for index in 0..<49 {
                    let progress = Double(index) / 48 * 100
                    context.stroke(tick(progress, inner: 0.78, outer: 0.92, center: center, radius: radius), with: .color(.white.opacity(0.5)), lineWidth: 1.4)
                }
                context.stroke(tick(percent, inner: 0.70, outer: 0.98, center: center, radius: radius), with: .color(Color(red: 1.0, green: 0.82, blue: 0.30)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
            VStack(spacing: 0) {
                Text(value).font(.title3.weight(.semibold)).monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
                if let unit { Text(unit).font(.caption2).foregroundStyle(HassTokens.Ink.onDarkSecondary) }
            }
            .offset(y: 4)
        }
        .aspectRatio(1.4, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func tick(_ percent: Double, inner: Double, outer: Double, center: CGPoint, radius: CGFloat) -> Path {
        let angle = (145 + min(100, max(0, percent)) / 100 * 250) * .pi / 180
        var path = Path()
        path.move(to: CGPoint(x: center.x + cos(angle) * radius * inner, y: center.y + sin(angle) * radius * inner))
        path.addLine(to: CGPoint(x: center.x + cos(angle) * radius * outer, y: center.y + sin(angle) * radius * outer))
        return path
    }
}
