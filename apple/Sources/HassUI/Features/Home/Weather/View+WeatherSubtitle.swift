import HassCore
import HassDesign
import SwiftUI

extension View {
    /// A subtitle under the navigation title where the system supports one (iOS 26); the hero says the same earlier.
    @ViewBuilder
    func weatherSubtitle(_ subtitle: String) -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            navigationSubtitle(subtitle)
        } else {
            self
        }
        #else
        self
        #endif
    }
}
