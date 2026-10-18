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
    #if os(iOS)
    @State private var handle = ProbeHandle()
    #endif

    func body(content: Content) -> some View {
        #if os(iOS)
        // A zoom destination says so through the environment; a plain push inherits `.push`.
        content
            .background { NavigationProbe(kind: kind == .push ? environmentKind : kind, page: page, handle: handle).allowsHitTesting(false) }
            // SwiftUI's own word that the page is going: UIKit may not forward the disappearance to the probe on a pop.
            .onDisappear { handle.controller?.pageDisappeared() }
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
    var handle: ProbeHandle

    func makeUIViewController(context: Context) -> NavigationProbeController {
        let controller = NavigationProbeController(kind: kind, page: page)
        handle.controller = controller
        return controller
    }

    func updateUIViewController(_ controller: NavigationProbeController, context: Context) {
        controller.kind = kind
        handle.controller = controller
    }
}

/// Lets the page's SwiftUI side reach the probe's controller.
@MainActor
final class ProbeHandle {
    weak var controller: NavigationProbeController?
}

/// The probe's view controller. It never trusts the `animated` flag of its own appearance callbacks: SwiftUI adds it to the
/// page's hosting controller after that controller has started appearing, so UIKit reports its appearance as not animated even
/// during a push. Instead a ``TransitionTracker`` watches the transition coordinators above it, frame by frame.
@MainActor
final class NavigationProbeController: UIViewController {
    var kind: NavigationKind
    private let page: String
    private var tracker: TransitionTracker?
    /// Whether the way out is already being timed (UIKit and SwiftUI both report it).
    private var timesLeaving = false

    init(kind: NavigationKind, page: String) {
        self.kind = kind
        self.page = page
        super.init(nibName: nil, bundle: nil)
        // The page being built is the closest thing to the intent the page can see.
        tracker = TransitionTracker(controller: self, measurement: .begin(kind.appear, page: page))
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func loadView() {
        view = UIView()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
    }

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        // Added to the hosting controller: the page is going on screen. A push or a presentation is under way right now or never.
        if parent != nil { tracker?.start() }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        pageDisappeared()
    }

    /// The page is going away: if it is the page itself (popped or dismissed), time that transition. Called from UIKit's
    /// `viewWillDisappear` and from SwiftUI's `onDisappear`, whichever arrives first.
    func pageDisappeared() {
        guard isLeaving, !timesLeaving else { return }
        timesLeaving = true
        // The page itself is going away: time that transition instead of the one that brought it here.
        tracker?.cancel()
        tracker = TransitionTracker(controller: self, measurement: .begin(kind.disappear, page: page))
        tracker?.start()
    }

    /// The controllers the page lives in: this one's parents, and the controllers its view sits in (the responder chain), each with
    /// their parents. SwiftUI may add the probe to a hosting controller above the pushed page's own, so both routes are walked.
    private var ancestors: [UIViewController] {
        var found: [UIViewController] = []
        func add(from start: UIViewController?) {
            var current = start
            while let controller = current {
                if !found.contains(where: { $0 === controller }) { found.append(controller) }
                current = controller.parent
            }
        }
        add(from: self)
        var responder: UIResponder? = isViewLoaded ? view : nil
        while let current = responder {
            if let controller = current as? UIViewController { add(from: controller) }
            responder = current.next
        }
        return found
    }

    /// Whether the page itself is going away (popped or dismissed), not merely covered by a page pushed above it.
    private var isLeaving: Bool {
        ancestors.contains { $0.isMovingFromParent || $0.isBeingDismissed }
    }

    /// Whether a push, pop, presentation or dismissal that includes this page is animating now.
    var isTransitioning: Bool {
        ancestors.contains { $0.transitionCoordinator != nil || $0.navigationController?.transitionCoordinator != nil }
    }
}

/// Watches one transition frame by frame and reports it to a ``NavigationMeasurement``: the first frame once a transition is seen
/// under way, settled when it ends. If no transition shows up within about half a second (a cold launch, a restored path, a tab
/// becoming visible), the measurement is cancelled and nothing is recorded.
@MainActor
final class TransitionTracker: NSObject {
    private weak var controller: NavigationProbeController?
    private let measurement: NavigationMeasurement
    private var link: CADisplayLink?
    private var frames = 0
    private var sawTransition = false

    /// Frames to wait for a transition to begin.
    static let patience = 40

    init(controller: NavigationProbeController, measurement: NavigationMeasurement) {
        self.controller = controller
        self.measurement = measurement
    }

    func start() {
        guard link == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func cancel() {
        link?.invalidate()
        link = nil
        measurement.cancel()
    }

    @objc private func tick(_ link: CADisplayLink) {
        frames += 1
        let transitioning = controller?.isTransitioning ?? false
        if transitioning {
            if !sawTransition {
                sawTransition = true
                measurement.firstFrame()
            }
        } else if sawTransition {
            link.invalidate()
            self.link = nil
            measurement.settled()
        } else if frames > Self.patience || controller == nil {
            cancel()
        }
    }
}
#endif
