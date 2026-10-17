import SwiftUI

/// The coordinate space of a todo page's `List`, in which the quick links' header and the plain rows are compared.
enum TodoListSpace {
    static let name = "hass.todoList"
}

extension EnvironmentValues {
    /// Called with the leading edge of a plain row (header, error, spinner, empty state) in the list's coordinate space:
    /// the list's own margin, where the modules and every tile and heading should start.
    @Entry var reportsRowOrigin: (CGFloat) -> Void = { _ in }
}

/// Lines a section header up with the rows of the same list.
///
/// A `List` section header sits inside the list's margin by an amount the system chooses (16 pt on an iPhone in a compact
/// window, other values elsewhere), and the Chores quick links live in one because a row of several `NavigationLink`s
/// fires all of them. This measures where the header starts and where a plain row starts and takes the difference back
/// with negative padding, so the tiles share the modules' edges in every size class, orientation and window width without a
/// fixed number. The measured view is the outer frame, which the padding inside does not move, so the measurement never
/// feeds back into itself.
struct AlignedToListMargins: ViewModifier {
    /// Where plain rows start, once one has reported.
    var rowOrigin: CGFloat?
    @State private var headerOrigin: CGFloat?

    /// How far the header sits inside the margin.
    var inset: CGFloat {
        guard let rowOrigin, let headerOrigin else { return 0 }
        return max(0, headerOrigin - rowOrigin)
    }

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, -inset)
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(TodoListSpace.name)).minX.rounded() } action: {
                headerOrigin = $0
            }
    }
}
