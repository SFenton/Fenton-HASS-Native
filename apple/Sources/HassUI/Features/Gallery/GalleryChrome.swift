#if DEBUG
import Foundation
import HassDesign
import SwiftUI

/// Switches the gallery pages read from the process environment.
enum GalleryEnvironment {
    /// `FENTON_GALLERY_CLEAN=1`: screenshots leave the debug line out.
    static var isClean: Bool { ProcessInfo.processInfo.environment["FENTON_GALLERY_CLEAN"] == "1" }
}

/// The debug line every gallery shows: the last service call (or action), which XCUITest journeys read through
/// the `gallery.lastCall` identifier to check what a control sent. Callers add their own padding and background.
struct GalleryLastCall: View {
    /// What the gallery recorded.
    var text: String
    /// The label before the text: `Last call` for service calls, `Last action` for galleries without a service.
    var title: String = "Last call"
    /// Lines before truncation; `nil` lets the line grow.
    var lineLimit: Int? = 3

    var body: some View {
        Text("\(title): \(text)")
            .font(.caption.monospaced())
            // Secondary ink measured 2.2:1 on the iPad sheet's bar.
            .foregroundStyle(HassTokens.Ink.primary)
            .lineLimit(lineLimit)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("gallery.lastCall")
    }
}
#endif
