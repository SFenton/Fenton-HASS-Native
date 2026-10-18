import FentonActivityModel
import HassCore
import HassDesign
import SwiftUI

/// The dark ground with its radial glow. At zero `glow` it is the plain launch colour, which is how the intro starts.
struct SignInGround: View {
    /// 0 is the plain ground, 1 the full glow.
    var glow: Double = 1

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(rgb: SignInStyle.base)
                RadialGradient(
                    stops: [
                        .init(color: Color(rgb: SignInStyle.glowCentre), location: 0),
                        .init(color: Color(rgb: SignInStyle.glowMiddle), location: 0.5),
                        .init(color: Color(rgb: SignInStyle.base), location: 1),
                    ],
                    center: UnitPoint(x: 0.5, y: 0.2), startRadius: 0, endRadius: max(proxy.size.width, proxy.size.height) * 0.95)
                    .opacity(glow)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
