import HassCore
@testable import HassUI
import SwiftUI
import Testing

/// The fade-out, swap, fade-in sequence behind tab changes and the vacuum's start-clean transition, driven by a
/// manual animator so each step can be checked.
@MainActor
struct SmoothContentSwapTests {
    /// Runs each animation's body at once and holds its completion until `step()`.
    @MainActor
    final class ManualAnimator {
        var pending: [@MainActor () -> Void] = []
        var animations: [Animation?] = []

        func animate(_ animation: Animation?, _ body: () -> Void, _ completion: @escaping @MainActor () -> Void) {
            animations.append(animation)
            body()
            pending.append(completion)
        }

        /// Finishes the oldest running animation.
        func step() { if !pending.isEmpty { pending.removeFirst()() } }

        /// Finishes every animation, including ones started by completions.
        func settle() { while !pending.isEmpty { step() } }
    }

    func make(_ initial: String = "a") -> (SmoothContentSwap<String>, ManualAnimator) {
        let animator = ManualAnimator()
        return (SmoothContentSwap(initial) { animator.animate($0, $1, $2) }, animator)
    }

    @Test func fadesOutSwapsThenFadesIn() {
        let (swap, animator) = make()
        var swaps: [String] = []
        swap.didSwap = { swaps.append($0) }
        swap.show("b")
        #expect(swap.isHidden)
        #expect(swap.displayed == "a", "The old content stays while it fades out")
        animator.step()
        #expect(swap.displayed == "b")
        #expect(swaps == ["b"], "Swapped while hidden, then the fade-in starts")
        #expect(!swap.isHidden)
        #expect(animator.pending.count == 1)
        animator.step()
        #expect(animator.pending.isEmpty)
        #expect(animator.animations.count == 2, "No layout animation by default")
    }

    @Test func sameKeyDoesNothing() {
        let (swap, animator) = make()
        swap.show("a")
        #expect(!swap.isHidden)
        #expect(animator.animations.isEmpty)
    }

    @Test func layoutChangesAnimateTheSwap() {
        let (swap, animator) = make()
        swap.animatesLayout = { $0 != $1 }
        var swaps: [String] = []
        swap.didSwap = { swaps.append($0) }
        swap.show("b")
        animator.step() // fade out done → layout animation starts
        #expect(swap.displayed == "b")
        #expect(swaps.isEmpty, "didSwap waits for the layout animation")
        animator.step() // layout done → fade in
        #expect(swaps == ["b"])
        animator.step()
        #expect(!swap.isHidden)
        #expect(animator.animations.count == 3)
    }

    @Test func rapidRequestsSettleOnTheLast() {
        let (swap, animator) = make()
        swap.show("b")
        swap.show("c") // during fade-out
        animator.step()
        #expect(swap.displayed == "c")
        swap.show("d") // during fade-in
        animator.settle()
        #expect(swap.displayed == "d")
        #expect(swap.target == "d")
        #expect(!swap.isHidden)
    }

    @Test func requestDuringTheSwapSwapsAgainWhileHidden() {
        let (swap, animator) = make()
        swap.animatesLayout = { _, _ in true }
        swap.show("b")
        animator.step() // layout animation for b running
        swap.show("c")
        animator.step() // layout done → target changed → swap again
        #expect(swap.displayed == "c")
        #expect(swap.isHidden)
        animator.settle()
        #expect(!swap.isHidden)
    }

    @Test func returningToTheShownKeyMidFadeRestoresIt() {
        let (swap, animator) = make()
        swap.show("b")
        swap.show("a")
        animator.settle()
        #expect(swap.displayed == "a")
        #expect(!swap.isHidden)
    }

    @Test func reduceMotionSwapsAtOnce() {
        let (swap, animator) = make()
        var swaps: [String] = []
        swap.didSwap = { swaps.append($0) }
        swap.show("b", reduceMotion: true)
        #expect(swap.displayed == "b")
        #expect(!swap.isHidden)
        #expect(animator.animations.isEmpty)
        #expect(swaps == ["b"])
        swap.show("b", reduceMotion: true)
        #expect(swaps == ["b"])
        // Reduce Motion mid-fade cancels the fade and the stale completion.
        swap.show("c")
        swap.show("d", reduceMotion: true)
        animator.settle()
        #expect(swap.displayed == "d")
        #expect(!swap.isHidden)
    }

    @Test func reduceMotionMidFadeDropsTheOldSequence() {
        let (swap, animator) = make()
        var swaps: [String] = []
        swap.didSwap = { swaps.append($0) }
        swap.show("b") // fade-out pending
        swap.show("c", reduceMotion: true)
        swap.show("d") // a new sequence while the old completion is still queued
        animator.settle()
        #expect(swap.displayed == "d")
        #expect(swaps == ["c", "d"], "The stale fade-out never swaps")
        #expect(!swap.isHidden)
    }

    @Test func swiftUIAnimatorRunsTheBodyAndCompletes() async {
        var ran = false
        SmoothContentSwap<String>.swiftUIAnimator(.default, { ran = true }) {}
        #expect(ran)
        let swap = SmoothContentSwap("a")
        #expect(swap.timing == .init())
    }

    // MARK: Vacuum sheet

    func vacuumContent(_ scenario: VacuumFixtures.Scenario, tab: VacuumTab) -> (VacuumSheetContent, VacuumController, EntityStore, ManualAnimator) {
        let store = VacuumFixtures.store(scenario)
        let controller = VacuumController(vacuum: Vacuums.all.first { !$0.zones.isEmpty && $0.dockControls != nil } ?? Vacuums.all[0],
                                          store: store, caller: NullCaller(), scheduler: ManualRevertScheduler())
        let animator = ManualAnimator()
        let content = VacuumSheetContent(tab: tab, controller: controller) { animator.animate($0, $1, $2) }
        return (content, controller, store, animator)
    }

    @Test func vacuumKeyFallsBackToControlsWhenTheModeHidesTheTab() {
        let (content, controller, _, _) = vacuumContent(.cleaning, tab: .zones)
        #expect(content.swap.displayed == .init(tab: .controls, mode: .minimal))
        #expect(VacuumSheetContent.key(requested: .info, controller: controller).tab == .info)
        #expect(content.selection(in: controller.tabs) == .controls)
        content.requestedTab = .info
        #expect(content.selection(in: controller.tabs) == .info)
    }

    @Test func startingACleanAnimatesTheCollapseAndKeepsTheTab() {
        let (content, controller, _, animator) = vacuumContent(.docked, tab: .controls)
        #expect(content.swap.displayed.mode == .full)
        controller.run(.clean)
        let next = VacuumSheetContent.key(requested: content.requestedTab, controller: controller)
        #expect(next == .init(tab: .controls, mode: .minimal))
        content.swap.show(next)
        animator.settle()
        #expect(content.swap.displayed == next)
        #expect(animator.animations.count == 3, "Fade out, layout collapse, fade in")
        #expect(content.scrollResets == 0, "Same tab: no scroll reset")
    }

    @Test func tabSwapsResetScrollOnlyWhenTheTabChanges() {
        let (content, controller, _, animator) = vacuumContent(.docked, tab: .controls)
        content.requestedTab = .info
        content.swap.show(VacuumSheetContent.key(requested: .info, controller: controller))
        animator.settle()
        #expect(content.swap.displayed.tab == .info)
        #expect(content.scrollResets == 1)
        #expect(animator.animations.count == 2, "A tab change only fades")
    }
}
