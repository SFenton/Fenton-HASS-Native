import HassCore
import HassDesign
import SwiftUI

/// The arrow drawn at 0 degrees: the head points down (the wind blows toward 180) and the dot sits on top (the source).
struct WindNeedle: View {
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
