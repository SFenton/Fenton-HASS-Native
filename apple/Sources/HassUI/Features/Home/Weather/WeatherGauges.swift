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

/// The arrow drawn at 0 degrees: the head points down (the wind blows toward 180) and the dot sits on top (the source).
private struct WindNeedle: View {
    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: size * 0.45, y: size * 0.50))
                    path.addLine(to: CGPoint(x: size * 0.55, y: size * 0.50))
                    path.addLine(to: CGPoint(x: size * 0.50, y: size * 0.74))
                    path.closeSubpath()
                }
                .fill(Color(red: 1.0, green: 0.82, blue: 0.30))
                Path { path in
                    path.move(to: CGPoint(x: size * 0.45, y: size * 0.50))
                    path.addLine(to: CGPoint(x: size * 0.55, y: size * 0.50))
                    path.addLine(to: CGPoint(x: size * 0.52, y: size * 0.32))
                    path.addLine(to: CGPoint(x: size * 0.48, y: size * 0.32))
                    path.closeSubpath()
                }
                .fill(HassTokens.Ink.onDark.opacity(0.55))
                Circle().fill(HassTokens.Ink.onDark).frame(width: size * 0.07, height: size * 0.07).position(x: size * 0.5, y: size * 0.29)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

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
