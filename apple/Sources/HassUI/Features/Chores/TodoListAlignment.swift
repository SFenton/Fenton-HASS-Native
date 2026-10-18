import Observation
import SwiftUI

/// What a todo page's plain rows tell its header, so the header can line up with them (``AlignedToListMargins``).
///
/// A reference type held once by the page and handed down through the environment, so the page's rows and header observe
/// only what they read: a closure in the environment was a new value on every evaluation of the page, which invalidated
/// every row that read it.
@MainActor
@Observable
final class TodoRowMetrics {
    /// How wide a plain row (header, error, spinner, empty state) is, once one has reported: the list's content width,
    /// inside its margins.
    var rowWidth: CGFloat?

    /// Records a plain row's width. Only a change is written, so a row that measures the same again wakes nobody.
    func report(rowWidth width: CGFloat) {
        if rowWidth != width { rowWidth = width }
    }

    /// How far a section header sits inside the list's margin: half the difference between the two widths, because the
    /// system sets a header in from both edges by the same amount.
    ///
    /// Widths, not positions: a position in the list's coordinate space changes on every frame of a scroll, and a read of it
    /// ran for every plain row on every frame (`.agents/testing/apple/performance.md`, Chores).
    /// - Parameters:
    ///   - rowWidth: A plain row's width, once one has reported.
    ///   - headerWidth: The header's width, once measured.
    /// - Returns: The inset, never negative; 0 until both are known.
    nonisolated static func headerInset(rowWidth: CGFloat?, headerWidth: CGFloat?) -> CGFloat {
        guard let rowWidth, let headerWidth else { return 0 }
        return max(0, (rowWidth - headerWidth) / 2)
    }
}

extension EnvironmentValues {
    /// The page's plain-row metrics; `nil` outside a todo page, where nothing reports and no header aligns.
    @Entry var todoRowMetrics: TodoRowMetrics?
}

/// Lines a section header up with the rows of the same list.
///
/// A `List` section header sits inside the list's margin by an amount the system chooses (16 pt on an iPhone in a compact
/// window, other values elsewhere), and the Chores quick links live in one because a row of several `NavigationLink`s
/// fires all of them. This measures how wide the header is and how wide a plain row is and takes the difference back with
/// negative padding, so the tiles share the modules' edges in every size class, orientation and window width without a
/// fixed number. The measured view is the outer frame, which the padding inside does not move, so the measurement never
/// feeds back into itself.
struct AlignedToListMargins: ViewModifier {
    @Environment(\.todoRowMetrics) private var metrics
    @State private var headerWidth: CGFloat?

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, -TodoRowMetrics.headerInset(rowWidth: metrics?.rowWidth, headerWidth: headerWidth))
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self) { $0.size.width.rounded() } action: { headerWidth = $0 }
    }
}
