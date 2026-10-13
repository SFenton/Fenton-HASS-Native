import HassCore
import HassDesign
import SwiftUI

/// The daylight arc with the sun at its progress (web `sunArc`).
struct WeatherSunArc: View {
    /// Daylight progress 0...100, or `nil` at night (no marker).
    var percent: Double?

    var body: some View {
        Canvas { context, size in
            let scaleX = size.width / 100
            let scaleY = size.height / 48
            func point(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * scaleX, y: y * scaleY) }
            var horizon = Path()
            horizon.move(to: point(4, 40))
            horizon.addLine(to: point(96, 40))
            context.stroke(horizon, with: .color(.white.opacity(0.35)), lineWidth: 1)
            var arc = Path()
            arc.move(to: point(8, 40))
            arc.addQuadCurve(to: point(92, 40), control: point(50, 4))
            context.stroke(arc, with: .color(.white.opacity(0.6)), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [3, 4]))
            if let percent {
                let marker = WeatherPresentation.sunArcMarker(percent: percent)
                let center = point(marker.x, marker.y)
                context.fill(Path(ellipseIn: CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10)), with: .color(Color(red: 1.0, green: 0.85, blue: 0.30)))
            }
        }
        .aspectRatio(100.0 / 48.0, contentMode: .fit)
        .frame(maxWidth: 200)
        .accessibilityHidden(true)
    }
}
