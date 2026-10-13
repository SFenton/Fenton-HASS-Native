import SwiftUI
#if os(iOS)
import UIKit
#endif

// MARK: - Swipe-to-dismiss attempt (iOS)

#if os(iOS)
/// Shows the discard confirmation when someone swipes down a sheet whose dismissal is
/// disabled because it holds unsaved input. HIG (Sheets): "If changes are unsaved when
/// swiping begins, confirm with an action sheet." SwiftUI has no public hook for the
/// attempt, so this wraps the presentation controller's delegate and forwards every other
/// call to SwiftUI's own delegate unchanged.
struct SheetDismissAttemptObserver: UIViewControllerRepresentable {
    let onAttempt: () -> Void

    func makeUIViewController(context: Context) -> Controller {
        Controller(onAttempt: onAttempt)
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.proxy.onAttempt = onAttempt
        controller.install()
    }

    final class Controller: UIViewController {
        let proxy: DelegateProxy

        init(onAttempt: @escaping () -> Void) {
            proxy = DelegateProxy(onAttempt: onAttempt)
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            install()
        }

        /// Insert the proxy on the presented root's presentation controller, once.
        func install() {
            var root: UIViewController = self
            while let parent = root.parent { root = parent }
            guard root.presentingViewController != nil,
                  let presentation = root.presentationController,
                  presentation.delegate !== proxy
            else { return }
            proxy.original = presentation.delegate
            presentation.delegate = proxy
        }
    }

    final class DelegateProxy: NSObject, UIAdaptivePresentationControllerDelegate {
        var onAttempt: () -> Void
        nonisolated(unsafe) weak var original: (any UIAdaptivePresentationControllerDelegate)?

        init(onAttempt: @escaping () -> Void) {
            self.onAttempt = onAttempt
        }

        func presentationControllerDidAttemptToDismiss(_ controller: UIPresentationController) {
            original?.presentationControllerDidAttemptToDismiss?(controller)
            onAttempt()
        }

        override nonisolated func responds(to selector: Selector!) -> Bool {
            super.responds(to: selector) || (original?.responds(to: selector) ?? false)
        }

        override nonisolated func forwardingTarget(for selector: Selector!) -> Any? {
            if let original, original.responds(to: selector) { return original }
            return super.forwardingTarget(for: selector)
        }
    }
}
#endif
