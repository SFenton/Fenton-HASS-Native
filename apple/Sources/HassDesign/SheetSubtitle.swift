import SwiftUI

public extension View {
    /// The one-line subtitle under a sheet's centred title (`.agents/design/direction-g.md`, Sheets: "Centred title
    /// plus a one-line subtitle"), such as "3 of 12 On" under Lights or "Live" under a camera.
    ///
    /// iOS 26 and later draw it as the system navigation subtitle, which follows the bar's Dynamic Type and Large
    /// Content Viewer rules. Earlier systems show the title alone: a custom principal title shrank instead of growing
    /// at AX5 and failed the humidifier audit (2026-10-13), and the subtitle only repeats what the sheet shows.
    /// - Parameter subtitle: The line, or nil for none.
    @ViewBuilder
    func sheetSubtitle(_ subtitle: String?) -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *), let subtitle, !subtitle.isEmpty {
            navigationSubtitle(subtitle)
        } else {
            self
        }
        #else
        self
        #endif
    }
}
