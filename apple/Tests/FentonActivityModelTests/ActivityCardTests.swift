import Foundation
@testable import FentonActivityModel
import Testing

struct ActivityCardTests {
    private let now = ActivityFixtures.now

    private func card(_ name: String, stale: Bool = false) throws -> ActivityCard {
        let fixture = try #require(HomeActivityFixtures.fixture(name, now: now))
        return ActivityCard(attributes: fixture.attributes, state: fixture.state, isStale: stale || fixture.isStale, now: now)
    }

    // MARK: Titles

    @Test func theHeadlineReplacesTheTitleAndTheDeviceStaysForSpeech() throws {
        let vacuum = try card("vacuum")
        #expect(vacuum.title == "Vacuuming Kitchen" && vacuum.deviceTitle == "Main Floor Vacuum")
        #expect(try card("fan").title == "Guest Bath Fan")
        var empty = vacuum.state
        empty.headline = ""
        #expect(ActivityCard(attributes: vacuum.attributes, state: empty).title == "Main Floor Vacuum")
        #expect(try card("hotflash-bysteph").detail == "Your side · by Steph")
        #expect(try card("fan").detail == nil)
        empty.detail = ""
        #expect(ActivityCard(attributes: vacuum.attributes, state: empty).detail == nil)
    }

    // MARK: Figure

    @Test func countdownsCountToTheEndAndShowHoursOnlyFromAnHour() throws {
        guard case let .countdown(range, showsHours, estimated) = try card("fan").figure else { Issue.record("not a countdown"); return }
        #expect(range.upperBound == now.addingTimeInterval(282) && !showsHours && !estimated)
        guard case let .countdown(_, longHours, _) = try card("fan-long").figure else { Issue.record("not a countdown"); return }
        #expect(longHours, "1:04:42 shows hours")
        guard case let .countdown(_, _, guess) = try card("dryer-estimated").figure else { Issue.record("not a countdown"); return }
        #expect(guess)
    }

    @Test func countUpsRunFromTheStartAndFreezeWhilePaused() throws {
        #expect(try card("dryer").figure == .countup(now.addingTimeInterval(-1_930)))
        #expect(try card("vacuum-paused").figure == .frozen(seconds: 760))
        // Paused with no frozen time: the time so far stands in.
        var paused = try card("vacuum-paused").state
        paused.value?.pausedElapsedS = nil
        let attributes = try card("vacuum").attributes
        #expect(ActivityCard(attributes: attributes, state: paused, now: now).figure == .frozen(seconds: 1_000))
        // Paused with neither.
        paused.value = ActivityValue(kind: .countup)
        #expect(ActivityCard(attributes: attributes, state: paused, now: now).figure == .none)
        // Running with no start shows nothing.
        var running = try card("vacuum").state
        running.value = ActivityValue(kind: .countup)
        #expect(ActivityCard(attributes: attributes, state: running, now: now).figure == .none)
    }

    @Test func percentsTextAndNothing() throws {
        #expect(try card("dishwasher-percent").figure == .percent(62))
        #expect(try card("hotflash-cooling").figure == .text("Cooling"))
        #expect(try card("dishwasher-waiting").figure == .text("Starts 5:10 PM"))
        let attributes = try card("fan").attributes
        func figure(_ state: HomeActivityState) -> ActivityCard.Figure { ActivityCard(attributes: attributes, state: state, now: now).figure }
        #expect(figure(HomeActivityState(value: .percent)) == .none, "percent needs progress")
        #expect(figure(HomeActivityState(value: .percent, progress: 3)) == .percent(100), "clamped")
        #expect(figure(HomeActivityState(value: .percent, progress: -1)) == .percent(0))
        #expect(figure(HomeActivityState(value: ActivityValue(kind: .text))) == .none)
        #expect(figure(HomeActivityState(value: .text(""))) == .none)
        #expect(figure(HomeActivityState(value: ActivityValue(kind: .countdown))) == .none, "a countdown needs an end")
        #expect(figure(HomeActivityState()) == .none)
    }

    @Test func aFinishedJobIsComplete() throws {
        for name in HomeActivityFixtures.completeNames {
            let complete = try card(name)
            #expect(complete.isComplete && complete.figure == .complete && complete.ring == .complete, Comment(rawValue: name))
            #expect(complete.buttons.isEmpty, "a finished card has no buttons")
            #expect(complete.spokenFigure == "complete")
        }
    }

    // MARK: Ring

    @Test func theRingFollowsTheKindOfFigure() throws {
        guard case .timer = try card("fan").ring else { Issue.record("a fan timer fills its ring with time"); return }
        #expect(try card("dryer").ring == .steady)
        #expect(try card("vacuum").ring == .steady)
        #expect(try card("dishwasher-percent").ring == .fraction(0.62))
        #expect(try card("hotflash-cooling").ring == .fraction(0.45))
        #expect(try card("dishwasher-waiting").ring == .track)
        #expect(try card("vacuum-paused").ring == .steady, "paused: steady, dimmed by the view")
        #expect(try card("vacuum-paused").isPaused)
        #expect(try card("dryer-estimated").ring == .track, "an estimate has no start, so no ring range")
        var paused = try card("fan").state
        paused.phase = .paused
        #expect(ActivityCard(attributes: try card("fan").attributes, state: paused, now: now).ring == .track, "a paused countdown stops filling")
        var over = try card("fan").state
        over.progress = 7
        over.value = nil
        #expect(ActivityCard(attributes: try card("fan").attributes, state: over, now: now).ring == .fraction(1))
    }

    // MARK: Style

    @Test func aProblemPhaseMakesAProblemCard() throws {
        let stuck = try card("problem-navigation-stuck")
        #expect(stuck.style == .problem(.critical) && stuck.problem?.code == "navigation.stuck")
        #expect(stuck.problemIslandLabel == "Needs help")
        var worded = stuck.state
        worded.value = .text("Stopped")
        #expect(ActivityCard(attributes: stuck.attributes, state: worded, now: now).problemIslandLabel == "Stopped", "the engine's wording wins")
        worded.value = nil
        #expect(ActivityCard(attributes: stuck.attributes, state: worded, now: now).problemIslandLabel == "Needs help", "else the severity's word")
        #expect(try card("problem-mop-clean_water_empty").style == .problem(.warning))
        #expect(try card("fan").style == .job && (try card("fan")).problem == nil && (try card("fan")).problemIslandLabel == nil)
        // A problem phase with no problem is a job card (a malformed push never blanks the card).
        var broken = stuck.state
        broken.problem = nil
        #expect(ActivityCard(attributes: stuck.attributes, state: broken, now: now).style == .job)
    }

    // MARK: Buttons

    @Test func buttonsAreNamedForTheirDeviceAndTheFirstIsPrimary() throws {
        let fan = try card("fan")
        #expect(fan.buttons.map(\.accessibilityLabel) == ["Stop Guest Bath Fan"])
        #expect(fan.buttons.first?.isPrimary == true)
        let vacuum = try card("vacuum")
        #expect(vacuum.buttons.map(\.accessibilityLabel) == ["Pause Main Floor Vacuum", "Dock Main Floor Vacuum"])
        #expect(vacuum.buttons.map(\.isPrimary) == [true, false])
        #expect(vacuum.buttons.map(\.id) == ["pause", "dock"])
        var promoted = vacuum.state
        promoted.controls[1].role = .primary
        #expect(ActivityCard(attributes: vacuum.attributes, state: promoted, now: now).buttons.map(\.isPrimary) == [true, true])
    }

    @Test func aJobCardKeepsTwoButtonsAndAProblemCardThreeWithDoneLast() throws {
        let stuck = try card("problem-navigation-stuck")
        #expect(stuck.buttons.map(\.id) == ["resume", "dock", "done"])
        #expect(stuck.islandButtons.map(\.id) == ["resume", "dock"], "the island shows two")
        var crowded = try card("fan").state
        crowded.controls = (0..<4).map { ActivityControl(id: "c\($0)", title: "C") }
        #expect(ActivityCard(attributes: try card("fan").attributes, state: crowded, now: now).buttons.count == 2)
        #expect(try card("washer").buttons.isEmpty)
    }

    // MARK: Pending

    @Test func aPendingPressReplacesTheButtonsWithItsLabel() throws {
        let pending = try card("fan-pending")
        #expect(pending.pendingLabel == "Stopping…" && pending.buttons.isEmpty && !pending.isUnconfirmed)
        let completing = try card("problem-completing")
        #expect(completing.pendingLabel == "Completing…" && completing.buttons.isEmpty)
    }

    @Test func aStalePendingPressGivesTheButtonsBackWithNotConfirmed() throws {
        let stale = try card("fan-pending-stale")
        #expect(stale.pendingLabel == nil && stale.isUnconfirmed)
        #expect(stale.buttons.map(\.id) == ["stop"], "the controls come back")
        #expect(ActivityCard.unconfirmedText == "Not confirmed")
        let plainStale = try card("fan", stale: true)
        #expect(!plainStale.isUnconfirmed && plainStale.buttons.count == 1, "stale without a press says nothing")
    }

    @Test func aNoticeIsKeptForOneUpdate() throws {
        let failed = try card("fan-notice")
        #expect(failed.notice == "Couldn't reach Home" && failed.buttons.map(\.id) == ["stop"] && failed.pendingLabel == nil)
        #expect(try card("fan").notice == nil)
        var blank = failed.state
        blank.notice = ""
        #expect(ActivityCard(attributes: failed.attributes, state: blank, now: now).notice == nil)
    }

    // MARK: Speech

    @Test func aProblemReadsAsOnePhrase() throws {
        #expect(try card("problem-navigation-stuck").spokenSummary
            == "Main Floor Vacuum, needs help: Stuck in Kitchen. Move it somewhere flat, then tap Resume.")
        #expect(try card("problem-mop-clean_water_empty").spokenSummary.hasPrefix("Main Floor Vacuum, needs attention: Clean water tank empty."))
        #expect(try card("problem-vendor-unknown_error_88").spokenSummary.hasSuffix(", Error 88"), "the chip is read too")
    }

    @Test func titlesCarryTheWordsThatMakeTheFigureASentence() throws {
        #expect(try card("dryer").spokenTitle == "Dryer, running for")
        #expect(try card("vacuum-paused").spokenTitle == "Paused in Kitchen, paused at")
        #expect(try card("dryer-estimated").spokenTitle == "Dryer, about")
        #expect(try card("fan").spokenTitle == "Guest Bath Fan, time left")
        #expect(try card("dishwasher-percent").spokenTitle == "Dishwasher")
    }

    @Test func figuresReadAsPhrases() throws {
        #expect(try card("fan").spokenFigure == "5 minutes left")
        #expect(try card("fan-long").spokenFigure == "1 hour 5 minutes left")
        #expect(try card("dryer-estimated").spokenFigure == "about 20 minutes left")
        #expect(try card("dryer").spokenFigure == "running for 32 minutes")
        #expect(try card("vacuum-paused").spokenFigure == "paused at 12 minutes")
        #expect(try card("dishwasher-percent").spokenFigure == "62 percent")
        #expect(try card("hotflash-cooling").spokenFigure == "Cooling")
        #expect(try card("hotflash-cooling").spokenSummary == "Hot Flash, Your side, Cooling")
        #expect(try card("washer-complete").spokenSummary == "Washing Machine, complete")
        #expect(ActivityCard(attributes: HomeActivityAttributes(), state: HomeActivityState(), now: now).spokenFigure == nil)
    }

    @Test func durationsAreSpokenInWholeUnits() {
        #expect(ActivityCard.spokenDuration(30) == "less than a minute")
        #expect(ActivityCard.spokenDuration(60) == "1 minute")
        #expect(ActivityCard.spokenDuration(125) == "2 minutes")
        #expect(ActivityCard.spokenDuration(3_600) == "1 hour")
        #expect(ActivityCard.spokenDuration(7_320) == "2 hours 2 minutes")
        #expect(ActivityCard.spokenDuration(61, roundingUp: true) == "2 minutes")
        #expect(ActivityCard.spokenRemaining(until: now, now: now) == "done")
        #expect(ActivityCard.spokenRemaining(until: now.addingTimeInterval(20), now: now) == "less than a minute left")
    }

    @Test func clocksFormatMinutesAndHours() {
        #expect(ActivityCard.clock(seconds: 760) == "12:40")
        #expect(ActivityCard.clock(seconds: 5) == "0:05")
        #expect(ActivityCard.clock(seconds: 3_882) == "1:04:42")
        #expect(ActivityCard.clock(seconds: -3) == "0:00")
    }
}
