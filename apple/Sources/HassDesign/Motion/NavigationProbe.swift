import HassTelemetry
import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Which navigation a page belongs to, so its appearance and disappearance are recorded under the right names.
public enum NavigationKind: Sendable {
    /// A page pushed on a `NavigationStack`: ``NavigationMeasurement/Surface/push`` and ``NavigationMeasurement/Surface/pop``.
    case push
    /// A sheet or cover: ``NavigationMeasurement/Surface/sheetPresent`` and ``NavigationMeasurement/Surface/sheetDismiss``.
    case sheet
    /// A zoom transition (iOS 18): ``NavigationMeasurement/Surface/zoomOpen`` and ``NavigationMeasurement/Surface/zoomClose``.
    case zoom

    var appear: NavigationMeasurement.Surface {
        switch self {
        case .push: .push
        case .sheet: .sheetPresent
        case .zoom: .zoomOpen
        }
    }

    var disappear: NavigationMeasurement.Surface {
        switch self {
        case .push: .pop
        case .sheet: .sheetDismiss
        case .zoom: .zoomClose
        }
    }
}

public extension EnvironmentValues {
    /// The kind of navigation the pages below belong to. A zoom destination sets `.zoom` so its page records `ZoomOpen`, not
    /// `Push`.
    @Entry var navigationKind: NavigationKind = .push
}

public extension View {
    /// Times this page's transition into and out of view: from the page being built (the intent) to its first frame and to
    /// the system transition settling, and the same on the way out, with the main thread's cost meanwhile
    /// (``NavigationMeasurement``). Apply it once to a pushed page (``pageChrome()``), a sheet (`hassSheet`) or a zoom
    /// destination. Does nothing on a page's non-animated appearances (a cold launch, a restored path).
    /// - Parameters:
    ///   - kind: The navigation kind; a zoom destination overrides it through the environment.
    ///   - page: The page's name for the log.
    func measuresNavigation(_ kind: NavigationKind, page: String) -> some View {
        modifier(MeasuresNavigation(kind: kind, page: page))
    }
}

private struct MeasuresNavigation: ViewModifier {
    var kind: NavigationKind
    var page: String
    @Environment(\.navigationKind) private var environmentKind

    func body(content: Content) -> some View {
        #if os(iOS)
        // A zoom destination says so through the environment; a plain push inherits `.push`.
        content.background { NavigationProbe(kind: kind == .push ? environmentKind : kind, page: page).allowsHitTesting(false) }
        #else
        content
        #endif
    }
}

#if os(iOS)
/// A zero-size view controller in the page's background. UIKit tells it when the page's transition starts and ends, which is
/// the only place the end of a push, a pop and a sheet is visible.
private struct NavigationProbe: UIViewControllerRepresentable {
    var kind: NavigationKind
    var page: String

    func makeUIViewController(context: Context) -> NavigationProbeController {
        NavigationProbeController(kind: kind, page: page)
    }

    func updateUIViewController(_ controller: NavigationProbeController, context: Context) {
        controller.kind = kind
    }
}

@MainActor
final class NavigationProbeController: UIViewController {
    var kind: NavigationKind
    private let page: String
    private var measurement: NavigationMeasurement?

    init(kind: NavigationKind, page: String) {
        self.kind = kind
        self.page = page
        super.init(nibName: nil, bundle: nil)
        // The page being built is the closest thing to the intent the page can see.
        measurement = .begin(kind.appear, page: page)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func loadView() {
        view = UIView()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard animated else {
            // A cold launch, a restored path, a tab becoming visible: not a transition.
            measurement?.cancel()
            measurement = nil
            return
        }
        // Coming back after a page above this one was popped is also animated; only a measurement in flight counts.
        guard let measurement else { return }
        NextFrame.perform { measurement.firstFrame() }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        measurement?.settled()
        measurement = nil
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        guard animated, isLeaving else { return }
        measurement?.cancel()
        let leaving = NavigationMeasurement.begin(kind.disappear, page: page)
        measurement = leaving
        NextFrame.perform { leaving.firstFrame() }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isLeaving { measurement?.settled() } else { measurement?.cancel() }
        measurement = nil
    }

    /// Whether the page itself is going away (popped or dismissed), not merely covered by a page pushed above it.
    private var isLeaving: Bool {
        var current: UIViewController? = self
        while let controller = current {
            if controller.isMovingFromParent || controller.isBeingDismissed { return true }
            current = controller.parent
        }
        return false
    }

}
#endif
