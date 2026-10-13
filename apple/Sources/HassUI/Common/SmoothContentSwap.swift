import Observation
import SwiftUI

/// Swaps a panel's content without a hard cut: the old content fades out, the new one is swapped in while hidden
/// (optionally animating the layout change, so a shorter panel collapses), then fades in. Web
/// `useSmoothDisplayedModalTab` (130 ms out, 170 ms in) and the vacuum's runtime content transition.
///
/// Views read ``displayed`` (what to draw) and ``isHidden`` (fade the panel); they call ``show(_:)`` with the key
/// they want. A key requested mid-transition is picked up at the next swap, so rapid taps settle on the last one.
/// With Reduce Motion the swap is immediate. Pattern: modal-sheet.
@MainActor
@Observable
final class SmoothContentSwap<Key: Equatable> {
    /// Durations, in seconds.
    struct Timing: Equatable {
        var fadeOut = 0.13
        var fadeIn = 0.17
        /// The swap's layout animation, when ``SmoothContentSwap/animatesLayout`` asks for one.
        var layout = 0.28
    }

    /// Runs `body` in an animation and calls `completion` when it finishes. Tests pass an immediate animator.
    typealias Animator = @MainActor (_ animation: Animation?, _ body: () -> Void, _ completion: @escaping @MainActor () -> Void) -> Void

    /// The key whose content is on screen.
    private(set) var displayed: Key
    /// The content is faded out (mid-transition).
    private(set) var isHidden = false
    /// The last key asked for.
    private(set) var target: Key

    @ObservationIgnored var timing = Timing()
    /// Whether the swap from one key to the next animates the layout (e.g. tabs collapsing). Default: never.
    @ObservationIgnored var animatesLayout: (Key, Key) -> Bool = { _, _ in false }
    /// Called right after each swap, while the content is hidden (e.g. to reset the scroll position).
    @ObservationIgnored var didSwap: (Key) -> Void = { _ in }
    @ObservationIgnored private let animator: Animator
    @ObservationIgnored private var running = false

    /// Creates the swapper showing `initial`.
    init(_ initial: Key, animator: @escaping Animator = SmoothContentSwap.swiftUIAnimator) {
        displayed = initial
        target = initial
        self.animator = animator
    }

    /// Asks for `key`'s content.
    /// - Parameter reduceMotion: Swap at once, without fades.
    func show(_ key: Key, reduceMotion: Bool = false) {
        target = key
        if reduceMotion {
            running = false
            isHidden = false
            guard displayed != key else { return }
            displayed = key
            didSwap(key)
            return
        }
        guard !running, displayed != key else { return }
        running = true
        animator(.easeOut(duration: timing.fadeOut), { isHidden = true }) { [weak self] in self?.swap() }
    }

    private func swap() {
        guard running else { return }
        let next = target
        let previous = displayed
        if next != previous, animatesLayout(previous, next) {
            animator(.easeInOut(duration: timing.layout), { displayed = next }) { [weak self] in
                self?.didSwap(next)
                self?.fadeIn()
            }
        } else {
            if next != previous {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { displayed = next }
                didSwap(next)
            }
            fadeIn()
        }
    }

    private func fadeIn() {
        guard running else { return }
        // A newer key arrived during the swap: swap again while still hidden.
        if target != displayed { swap(); return }
        animator(.easeOut(duration: timing.fadeIn), { isHidden = false }) { [weak self] in
            guard let self else { return }
            running = false
            if target != displayed { show(target) }
        }
    }

    /// The app's animator: `withAnimation` with a logically-complete completion.
    static func swiftUIAnimator(_ animation: Animation?, _ body: () -> Void, _ completion: @escaping @MainActor () -> Void) {
        withAnimation(animation, completionCriteria: .logicallyComplete, body) { MainActor.assumeIsolated { completion() } }
    }
}
