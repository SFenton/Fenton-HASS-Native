#if os(iOS)
import HassDesign
import SwiftUI
import UIKit

/// Holds the navigation bar (the large title and the header buttons) and the tab bar back while Home arrives after a sign-in,
/// then brings them in: the header fades up 10 pt, the tab bar rises from the bottom (`HomeArrival`).
///
/// Both bars are UIKit's, out of SwiftUI's animation reach, so a probe in the page finds them from its view controller and
/// animates their alpha and transform. Nothing happens unless an arrival is under way, so a relaunch, a tab switch or a
/// reconnect never touches the bars; and a probe that goes away puts the bars back, so a hold can never strand them.
struct ArrivalChromeProbe: View {
    @Environment(\.homeArrival) private var arrival
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ArrivalChromeRepresentable(isHolding: arrival.map { $0.isActive && !$0.isRevealed } ?? false, reduceMotion: reduceMotion)
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct ArrivalChromeRepresentable: UIViewRepresentable {
    var isHolding: Bool
    var reduceMotion: Bool

    func makeUIView(context: Context) -> ArrivalChromeView {
        let view = ArrivalChromeView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: ArrivalChromeView, context: Context) {
        let holding = isHolding, reduceMotion = reduceMotion
        // Next turn: on the first update the view is not in a window yet.
        Task { @MainActor [weak view] in view?.apply(isHolding: holding, reduceMotion: reduceMotion) }
    }
}

final class ArrivalChromeView: UIView {
    private var held = false
    private weak var navigationBar: UINavigationBar?
    private weak var tabBar: UITabBar?

    func apply(isHolding: Bool, reduceMotion: Bool) {
        if isHolding, !held {
            guard let bars = findBars() else { return }
            held = true
            navigationBar = bars.navigation
            tabBar = bars.tab
            bars.navigation.alpha = 0
            bars.navigation.transform = CGAffineTransform(translationX: 0, y: reduceMotion ? 0 : 10)
            if let tab = bars.tab {
                tab.alpha = 0
                tab.transform = CGAffineTransform(translationX: 0, y: reduceMotion ? 0 : 48)
            }
        } else if !isHolding, held {
            release(animated: true, reduceMotion: reduceMotion)
        }
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow == nil, held { release(animated: false, reduceMotion: true) }
    }

    private func release(animated: Bool, reduceMotion: Bool) {
        held = false
        let navigation = navigationBar, tab = tabBar
        guard animated else {
            for bar in [navigation, tab] { bar?.alpha = 1; bar?.transform = .identity }
            return
        }
        let fade = reduceMotion ? 0.35 : 0.4
        UIView.animate(withDuration: fade, delay: reduceMotion ? 0 : 0.1, options: [.curveEaseOut, .allowUserInteraction]) {
            navigation?.alpha = 1
            navigation?.transform = .identity
        }
        UIView.animate(withDuration: fade, delay: reduceMotion ? 0 : 0.22, options: [.curveEaseOut, .allowUserInteraction]) {
            tab?.alpha = 1
            tab?.transform = .identity
        }
    }

    private func findBars() -> (navigation: UINavigationBar, tab: UITabBar?)? {
        var responder: UIResponder? = self
        while let current = responder, !(current is UIViewController) { responder = current.next }
        guard let controller = responder as? UIViewController, let navigation = controller.navigationController else { return nil }
        return (navigation.navigationBar, controller.tabBarController?.tabBar)
    }
}
#endif
