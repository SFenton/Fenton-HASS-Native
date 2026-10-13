@testable import HassDesign
import SwiftUI
import Testing

/// ``ContentGateModel`` and ``ReadinessTracker``: the web's spinner/content phase sequence.
@MainActor
struct ContentGateTests {
    /// Records each wait and returns at once.
    @MainActor final class Sleeps {
        var waited: [Duration] = []
        var cancelAt: Duration?
        func sleep(_ duration: Duration) async -> Bool {
            waited.append(duration)
            return duration != cancelAt
        }
    }

    private func make(isReady: Bool) -> (ContentGateModel, Sleeps) {
        let sleeps = Sleeps()
        let model = ContentGateModel(page: "Test", isReady: isReady) { await sleeps.sleep($0) }
        return (model, sleeps)
    }

    @Test func readyAtCreationNeverShowsASpinner() async {
        let (model, sleeps) = make(isReady: true)
        #expect(model.phase == .idle)
        await model.advance(isReady: true)
        #expect(model.phase == .idle)
        #expect(!model.spinnerShown)
        #expect(sleeps.waited.isEmpty)
    }

    @Test func coldLoadFadesSpinnerInThenOutThenContentIn() async {
        let (model, sleeps) = make(isReady: false)
        #expect(model.phase == .loading)
        #expect(!model.phase.showsContent)
        await model.advance(isReady: false)
        #expect(model.spinnerShown)
        await model.advance(isReady: true)
        #expect(model.phase == .idle)
        #expect(!model.spinnerShown)
        typealias T = ContentGateModel.Timing
        #expect(sleeps.waited == [T.spinnerDelay, T.spinnerExit, T.contentEnter])
    }

    @Test func fastLoadSkipsTheSpinner() async {
        let (model, sleeps) = make(isReady: false)
        await model.advance(isReady: true)
        #expect(model.phase == .idle)
        #expect(sleeps.waited == [ContentGateModel.Timing.contentEnter])
    }

    @Test func waitsForReportedContentUpToTheTimeout() async {
        let (model, sleeps) = make(isReady: false)
        model.tracker.set("image:a", ready: false)
        #expect(!model.tracker.isSettled)
        // The view re-runs `advance` when the tracker settles; a cancelled wait leaves the gate loading.
        sleeps.cancelAt = ContentGateModel.Timing.childTimeout
        await model.advance(isReady: true)
        #expect(model.phase == .loading)
        model.tracker.set("image:a", ready: true)
        model.tracker.set("image:a", ready: true)
        #expect(model.tracker.isSettled)
        sleeps.cancelAt = nil
        await model.advance(isReady: true)
        #expect(model.phase == .idle)

        // Timeout path: a stuck image doesn't hold the page forever.
        let (stuck, stuckSleeps) = make(isReady: false)
        stuck.tracker.set("image:slow", ready: false)
        await stuck.advance(isReady: true)
        #expect(stuck.phase == .idle)
        #expect(stuckSleeps.waited.first == ContentGateModel.Timing.childTimeout)
    }

    @Test func reloadFadesContentOutThenShowsTheSpinner() async {
        let (model, sleeps) = make(isReady: true)
        await model.advance(isReady: false)
        #expect(model.phase == .loading)
        #expect(model.spinnerShown)
        #expect(sleeps.waited == [ContentGateModel.Timing.contentExit, ContentGateModel.Timing.spinnerDelay])
        await model.advance(isReady: false)
        #expect(sleeps.waited.count == 2)
    }

    @Test func interruptedTransitionsResume() async {
        let (model, sleeps) = make(isReady: false)
        await model.advance(isReady: false)
        sleeps.cancelAt = ContentGateModel.Timing.spinnerExit
        await model.advance(isReady: true)
        #expect(model.phase == .spinnerExiting)
        sleeps.cancelAt = ContentGateModel.Timing.contentEnter
        await model.advance(isReady: true)
        #expect(model.phase == .entering)
        #expect(model.phase.showsContent)
        await model.advance(isReady: true)
        #expect(model.phase == .idle)

        let (exiting, exitSleeps) = make(isReady: true)
        exitSleeps.cancelAt = ContentGateModel.Timing.contentExit
        await exiting.advance(isReady: false)
        #expect(exiting.phase == .exiting)
    }

    @Test func productionSleepReportsCancellation() async {
        #expect(await ContentGateModel.taskSleep(.zero))
        let task = Task { await ContentGateModel.taskSleep(.seconds(10)) }
        task.cancel()
        #expect(await task.value == false)
    }

    @Test func gateRendersEveryPhase() {
        for ready in [true, false] {
            let gate = ContentGate(page: "Render", isReady: ready) {
                Text("Content").contentReadiness("text", isReady: true)
            }
            #expect(ImageRenderer(content: gate.frame(width: 200, height: 200)).cgImage != nil)
        }
    }
}
