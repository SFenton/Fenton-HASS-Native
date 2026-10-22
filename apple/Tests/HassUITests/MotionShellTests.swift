import Foundation
import HassCore
import HassTelemetry
@testable import HassUI
import SwiftUI
import Testing

/// Tabs, the session's motion memory and the Navigation section of Performance (design: `.agents/design/motion.md` §3, §4.1, §10).
@MainActor
struct MotionShellTests {
    // MARK: Tabs

    @Test func tappingAnotherTabIsACutAndKeepsTheOtherPaths() {
        let navigator = ShellNavigator()
        navigator.paths[.home] = NavigationPath(["room"])
        navigator.tabTapped(.security)
        #expect(navigator.selection == .security)
        #expect(!navigator.isAtRoot(.home), "each tab keeps its own path")
        #expect(navigator.scrollToTopRequests.isEmpty)
        navigator.tabTapped(.home)
        #expect(navigator.selection == .home && !navigator.isAtRoot(.home))
    }

    @Test func theSecondTapPopsToTheRootAndTheThirdScrollsToTheTop() {
        let navigator = ShellNavigator()
        navigator.paths[.home] = NavigationPath(["room", "sheet"])
        #expect(navigator.reselect(.home) == .poppedToRoot)
        #expect(navigator.isAtRoot(.home))
        #expect(navigator.scrollToTopRequests[.home] == nil, "popping does not also scroll")
        #expect(navigator.reselect(.home) == .scrolledToTop)
        #expect(navigator.scrollToTopRequests[.home] == 1)
        navigator.tabTapped(.home)
        #expect(navigator.scrollToTopRequests[.home] == 2, "a tap on the selected tab at its root asks again")
        #expect(navigator.scrollToTopRequests[.security] == nil)
    }

    @Test func theFlyoutFollowsTheSameRule() {
        let navigator = ShellNavigator()
        navigator.paths[.home] = NavigationPath(["room"])
        navigator.openFlyout()
        navigator.select(.home)
        #expect(navigator.isAtRoot(.home) && !navigator.isFlyoutOpen)
        navigator.select(.home)
        #expect(navigator.scrollToTopRequests[.home] == 1)
    }

    @Test func aNotificationForAnotherSectionOpensItsRoot() {
        let navigator = ShellNavigator()
        navigator.open(.section(.security))
        #expect(navigator.selection == .security && navigator.isAtRoot(.security))
    }

    // MARK: Session

    @Test func signingOutResetsTheMomentsSoTheNextSignInPlaysAgain() throws {
        let cache = EntitySnapshotCache(fileURL: FileManager.default.temporaryDirectory.appending(path: "motion-\(UUID()).json"))
        let motion = MotionPolicy(reduceMotion: { false })
        let session = AppSession(tokenStore: InMemoryTokenStore(), snapshotCache: cache, motion: motion)
        #expect(session.motion === motion && !motion.hasPlayed(.signInArrival))
        try session.didSignIn(server: HassServer(baseURL: URL(string: "http://127.0.0.1:1")!),
                              tokens: AuthTokens(accessToken: "a", expiresAt: .distantFuture, refreshToken: "r"))
        #expect(!motion.hasPlayed(.signInArrival), "signing in does not mark the arrival: it is about to play")
        motion.markPlayed(.signInArrival)
        motion.markPlayed(.intro)
        session.signOut()
        #expect(motion.played.isEmpty)
    }

    @Test func resumingASavedSignInIsNotAnArrival() throws {
        let store = InMemoryTokenStore()
        try store.save(StoredCredentials(server: HassServer(baseURL: URL(string: "http://127.0.0.1:1")!), refreshToken: "saved"))
        let cache = EntitySnapshotCache(fileURL: FileManager.default.temporaryDirectory.appending(path: "motion-\(UUID()).json"))
        let motion = MotionPolicy(reduceMotion: { false })
        let session = AppSession(tokenStore: store, snapshotCache: cache, motion: motion)
        #expect(motion.hasPlayed(.signInArrival), "a cold launch while signed in shows no arrival")
        #expect(!motion.hasPlayed(.intro))
        session.signOut()
    }

    // MARK: Revisits

    @Test func sessionModelsAreMadeOnceAndSharedByEveryVisit() throws {
        let cache = EntitySnapshotCache(fileURL: FileManager.default.temporaryDirectory.appending(path: "motion-\(UUID()).json"))
        let session = AppSession(tokenStore: InMemoryTokenStore(), snapshotCache: cache)
        try session.didSignIn(server: HassServer(baseURL: URL(string: "http://127.0.0.1:1")!),
                              tokens: AuthTokens(accessToken: "a", expiresAt: .distantFuture, refreshToken: "r"))
        guard case let .signedIn(connection, _) = session.phase else { Issue.record("expected signed in"); return }
        let models = SessionModels()
        #expect(models.food === models.food)
        #expect(models.inventory(for: connection) === models.inventory(for: connection), "a revisit finds the inventory already loaded")
        #expect(SessionModels().food !== models.food, "a new session starts empty")
        session.signOut()
    }

    @Test func theFoodHubRendersOnTheSessionsModels() {
        let models = FoodModels()
        #expect(models.suggestions.phase == .idle)
        let hub = FoodHubScreen(models: models).environment(\.sessionModels, SessionModels())
        #expect(ImageRenderer(content: hub.frame(width: 402, height: 874)).cgImage != nil)
    }

    // MARK: Performance

    @Test func navigationRowsComeFromThePhaseStats() throws {
        let log = TelemetryLog()
        for ms in [20.0, 30, 40] { log.record(TelemetryRecord(kind: "Push", page: "Room", durationMs: ms, detail: "settled")) }
        for ms in [5.0, 6, 7] { log.record(TelemetryRecord(kind: "Push", page: "Room", durationMs: ms, detail: "firstFrame")) }
        log.record(TelemetryRecord(kind: "Push", page: "Room", value: 4, detail: "p95Turn"))
        log.record(TelemetryRecord(kind: "Push", page: "Room", value: 9, detail: "worstTurn"))
        log.record(TelemetryRecord(kind: "TabSwitch", page: "Home", durationMs: 12, detail: "firstFrame"))
        log.record(TelemetryRecord(kind: "SheetPresent", page: "Hall", value: 3, detail: "worstTurn"))
        let rows = NavigationTelemetry.rows(from: log.phaseStats)
        #expect(rows.map(\.surface) == [.tabSwitch, .push], "a surface with no first frame or settled sample has no row")
        let push = try #require(rows.last)
        #expect(push.id == "push" && push.count == 3)
        #expect(push.settled?.p50 == 30 && push.firstFrame?.p95 == 7)
        #expect(push.turnP95?.max == 4 && push.turnWorst?.max == 9)
        #expect(rows.first?.count == 1)
    }

    @Test func theNavigationSectionReadsAndTones() throws {
        let row = NavigationTelemetry.Row(
            surface: .push, firstFrame: TelemetryStats([5, 6, 7]), settled: TelemetryStats([300, 320, 340]),
            turnP95: TelemetryStats([4]), turnWorst: TelemetryStats([12]))
        #expect(PerformanceScreen.navigationValue(row) == "320 ms")
        let detail = PerformanceScreen.navigationDetail(row)
        #expect(detail.contains("first frame p50 6") && detail.contains("settled p50 320") && detail.contains("worst turn 12 ms"))
        #expect(PerformanceScreen.navigationTone(row) == .good)
        var warm = row
        warm.turnP95 = TelemetryStats([12])
        #expect(PerformanceScreen.navigationTone(warm) == .warning)
        warm.turnP95 = TelemetryStats([40])
        #expect(PerformanceScreen.navigationTone(warm) == .bad)
        var empty = row
        empty.turnP95 = nil
        empty.settled = nil
        #expect(PerformanceScreen.navigationTone(empty) == .neutral)
        #expect(PerformanceScreen.navigationValue(empty) == "6 ms")
        empty.firstFrame = nil
        #expect(PerformanceScreen.navigationValue(empty) == "-")
    }

    @Test func theReportCarriesNavigationAndTheScreenRenders() {
        let wasEnabled = Telemetry.isEnabled
        defer { Telemetry.isEnabled = wasEnabled }
        Telemetry.isEnabled = true
        let page = "report-\(UUID().uuidString)"
        NavigationMeasurement.begin(.sheetPresent, page: page, measuresCost: false).settled()
        let report = PerformanceReport.current()
        #expect(report.navigation.contains { $0.surface == .sheetPresent })
        #expect(ImageRenderer(content: NavigationStack { PerformanceScreen() }.frame(width: 402, height: 874)).cgImage != nil)
    }
}
