#if os(macOS)
import AppKit
import Foundation
import HassCore
import HassDesign
import HassTelemetry
@testable import HassUI
import SwiftUI
import Testing

extension LoginTests {
/// What a session does when Home Assistant rejects the token, the launch and sign-in choreography in the root, and the
/// reconnecting chip.
@MainActor
@Suite(.serialized)
struct SignInMotionTests {
    static let server = AppSessionTests.server
    static let tokens = AppSessionTests.tokens

    func defaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "motion.tests.\(UUID())"))
    }

    func session(remembering username: String? = nil, name: String? = nil, defaults: UserDefaults? = nil) throws -> (AppSession, UserDefaults) {
        let defaults = try defaults ?? self.defaults()
        let remembered = RememberedAccountStore(defaults: defaults)
        if let username { remembered.remember(username: username) }
        if let name { defaults.set(name, forKey: RememberedAccountStore.nameKey) }
        let cache = EntitySnapshotCache(fileURL: FileManager.default.temporaryDirectory.appending(path: "motion-\(UUID()).json"))
        return (AppSession(tokenStore: InMemoryTokenStore(), snapshotCache: cache, remembered: remembered), defaults)
    }

    // MARK: Session expiry

    @Test func aRejectedSessionKeepsWhoItWasForTheWelcomeBack() throws {
        let (session, _) = try session(remembering: "stephen", name: "Stephen Fenton")
        #expect(!session.isSignedIn && session.expiredAccount == nil)
        try session.didSignIn(server: Self.server, tokens: Self.tokens)
        #expect(session.isSignedIn)
        session.sessionExpired()
        #expect(!session.isSignedIn)
        #expect(session.expiredAccount == RememberedAccount(username: "stephen", name: "Stephen Fenton"))
        session.forgetExpiredAccount()
        #expect(session.expiredAccount == nil)
    }

    @Test func signingInAgainClearsTheExpiredAccount() throws {
        let (session, _) = try session(remembering: "stephen")
        try session.didSignIn(server: Self.server, tokens: Self.tokens)
        session.sessionExpired()
        #expect(session.expiredAccount != nil)
        try session.didSignIn(server: Self.server, tokens: Self.tokens)
        #expect(session.expiredAccount == nil)
        session.signOut()
        #expect(session.expiredAccount == nil, "a deliberate sign-out is not an expired session")
    }

    @Test func aPhoneThatNeverRememberedAUsernameGetsThePlainSignIn() throws {
        let (session, _) = try session()
        try session.didSignIn(server: Self.server, tokens: Self.tokens)
        session.sessionExpired()
        #expect(session.expiredAccount == nil)
    }

    @Test func forgettingTheAccountForgetsTheUsernameToo() throws {
        let (session, defaults) = try session(remembering: "stephen", name: "Stephen")
        session.forgetExpiredAccount()
        #expect(RememberedAccountStore(defaults: defaults).account == nil)
    }

    @Test func aDebugLaunchCanStartAsIfASessionJustEnded() async throws {
        let account = await withLaunch(environment: ["FENTON_EXPIRED_ACCOUNT": "stephen|Stephen Fenton"]) { (try? session())?.0.expiredAccount }
        #expect(account == RememberedAccount(username: "stephen", name: "Stephen Fenton"))
        let bare = await withLaunch(environment: ["FENTON_EXPIRED_ACCOUNT": "stephen"]) { (try? session())?.0.expiredAccount }
        #expect(bare == RememberedAccount(username: "stephen", name: nil))
    }

    @Test func aUITestResetForgetsTheRememberedAccount() async throws {
        let defaults = try defaults()
        RememberedAccountStore(defaults: defaults).remember(username: "stephen")
        let session = await withLaunch(environment: ["FENTON_UITEST_RESET": "1"]) { try? self.session(defaults: defaults).0 }
        #expect(session?.expiredAccount == nil)
        #expect(RememberedAccountStore(defaults: defaults).account == nil)
    }

    @Test func theLaunchIntervalsOpenAtStart() {
        AppSession.beginLaunchMeasurement()
        #expect(Telemetry.isTracked(Telemetry.Name.launch) && Telemetry.isTracked(Telemetry.Name.snapshotShown))
        Telemetry.cancelTracked(Telemetry.Name.launch)
        Telemetry.cancelTracked(Telemetry.Name.snapshotShown)
    }

    // MARK: Root

    @Test func theIntroPlaysOnAColdLaunchOnlyAndADebugLaunchCanSkipIt() {
        #expect(RootView.playsIntro(played: false, environment: [:]))
        #expect(!RootView.playsIntro(played: true, environment: [:]))
        #expect(!RootView.playsIntro(played: false, environment: ["FENTON_SKIP_INTRO": "1"]))
    }

    @Test func theRootShowsTheWelcomeBackForAnExpiredSession() async throws {
        let (plain, _) = try session()
        let (expired, _) = try session(remembering: "stephen", name: "Stephen Fenton")
        try expired.didSignIn(server: Self.server, tokens: Self.tokens)
        expired.sessionExpired()
        let first = HostedWindow(RootView(session: plain), size: LoginTests.LoginViewTests.phone)
        let second = HostedWindow(RootView(session: expired), size: LoginTests.LoginViewTests.phone)
        defer { first.close(); second.close() }
        await first.settle(1.0)
        await second.settle(1.0)
        let fresh = try #require(first.snapshot())
        let welcome = try #require(second.snapshot())
        #expect(welcome.differs(from: fresh), "the monogram and one field, not the mark and two")
    }

    @Test func aSignInLiftsTheLayerWhileHomeArrivesUnderItThenTheLayerGoes() async throws {
        try await withLaunch(environment: [
            "FENTON_SIGNIN_STUB": "success", "FENTON_HASS_SERVER": "http://127.0.0.1:1", "FENTON_HASS_USERNAME": "stephen",
            "FENTON_HASS_PASSWORD": "pw", "FENTON_SKIP_INTRO": "1",
        ]) {
            let (session, _) = try session()
            let driver = AXWindow(RootView(session: session), size: LoginTests.LoginViewTests.phone)
            defer { driver.close(); session.signOut() }
            let before = try #require(driver.window.snapshot())
            let ready = await driver.wait { nodes in nodes.contains { $0.identifier == "login.submit" && $0.isEnabled } }
            #expect(ready.contains { $0.identifier == "login.submit" && $0.isEnabled }, "the debug launch filled both fields")
            #expect(await driver.press("login.submit") { _ in session.isSignedIn })
            // The layer is still up while it lifts, then it is gone and Home shows alone.
            await driver.window.settle(0.2)
            await driver.window.settle(1.5)
            let after = try #require(driver.window.snapshot())
            #expect(after.differs(from: before))
            let gone = await driver.wait { !$0.contains { $0.identifier == "login.submit" } }
            #expect(!gone.contains { $0.identifier == "login.submit" }, "the sign-in layer is removed once it has lifted away")
        }
    }

    @Test func onlyARefusedTokenEndsTheSession() throws {
        let (session, _) = try session(remembering: "stephen", name: "Stephen")
        try session.didSignIn(server: Self.server, tokens: Self.tokens)
        for status: HassConnection.Status in [.connecting, .connected(version: "x"), .waitingToReconnect, .disconnected] {
            session.connectionStatusChanged(status)
            #expect(session.isSignedIn, "\(status) is not a refusal")
        }
        session.connectionStatusChanged(.rejected)
        #expect(!session.isSignedIn)
        #expect(session.expiredAccount?.username == "stephen")
    }

    // MARK: Motion policy

    @Test func aMomentPlaysOncePerSessionAndSigningOutResetsIt() throws {
        let (session, _) = try session()
        let motion = session.motion
        #expect(Moment.allCases == [.intro, .signInArrival])
        #expect(!motion.hasPlayed(.intro) && !motion.hasPlayed(.signInArrival))
        motion.markPlayed(.intro)
        #expect(motion.hasPlayed(.intro) && !motion.hasPlayed(.signInArrival))
        motion.markPlayed(.signInArrival)
        try session.didSignIn(server: Self.server, tokens: Self.tokens)
        #expect(motion.hasPlayed(.signInArrival), "signing in does not reset it")
        session.signOut()
        #expect(!motion.hasPlayed(.intro) && !motion.hasPlayed(.signInArrival), "signing out does")
        _ = motion.reduceMotion
    }

    // MARK: Arrival

    @Test func anArrivalHoldsElementsBackUntilItIsRevealedAndFinishes() {
        let arrival = HomeArrival()
        #expect(!arrival.isActive && arrival.isRevealed, "at rest, everything is in place")
        arrival.begin()
        #expect(arrival.isActive && !arrival.isRevealed)
        arrival.reveal()
        #expect(arrival.isActive && arrival.isRevealed)
        arrival.finish()
        #expect(!arrival.isActive && arrival.isRevealed)
    }

    @Test func theStaggerRunsSixtyMillisecondsApartForTheFirstScreenfulOnly() {
        #expect(HomeArrival.riseDelay(index: 0) == 0.20)
        #expect(abs(HomeArrival.riseDelay(index: 1) - 0.26) < 0.0001)
        #expect(HomeArrival.riseDelay(index: 5) == HomeArrival.riseDelay(index: 50), "the rest come in with the last staggered one")
        #expect(HomeArrival.riseDelay(index: -3) == HomeArrival.riseDelay(index: 0))
        #expect(HomeArrival.duration == .milliseconds(900))
        #expect(MotionTokens.arrivalStagger == 0.06 && HomeArrival().moment == .signInArrival)
    }

    @Test func elementsDrawHeldBackDuringAnArrivalAndInPlaceAfterIt() async throws {
        func draw(arrival: HomeArrival?, reveal: Bool) async throws -> NSBitmapImageRep {
            if reveal { arrival?.reveal() }
            let hosted = HostedWindow(
                VStack {
                    Text("Chips").arrivalMotion(kind: .slideIn)
                    Text("Tile").arrivalMotion(index: 2)
                }
                .font(.largeTitle)
                .environment(\.homeArrival, arrival),
                size: CGSize(width: 300, height: 200))
            defer { hosted.close() }
            await hosted.settle(1.3)
            return try #require(hosted.snapshot())
        }
        let holding = HomeArrival()
        holding.begin()
        let held = try await draw(arrival: holding, reveal: false)
        let shown = try await draw(arrival: holding, reveal: true)
        let atRest = try await draw(arrival: nil, reveal: false)
        #expect(shown.differs(from: held), "held back, the elements are invisible")
        #expect(!shown.differs(from: atRest), "once revealed they sit where they would with no arrival")
    }

    // MARK: Reconnecting chip

    @Test func theChipWaitsOutAShortOutageAndGoesWhenLive() async throws {
        func draw(_ status: HassConnection.Status?, delay: Duration, wait: TimeInterval = 1.5) async throws -> NSBitmapImageRep {
            let hosted = HostedWindow(
                Color.black.modifier(ReconnectingOverlay(headerEnd: 40, statusOverride: status, delay: delay)),
                size: CGSize(width: 402, height: 300))
            defer { hosted.close() }
            await hosted.settle(wait)
            return try #require(hosted.snapshot())
        }
        // The delay is shortened (the policy's own two seconds are tested on their own): long enough never to pass, and short.
        let live = try await draw(.connected(version: "x"), delay: .milliseconds(50))
        let soon = try await draw(.waitingToReconnect, delay: .seconds(600))
        #expect(!soon.differs(from: live), "no chip yet: the outage has not lasted its delay")
        let later = try await draw(.waitingToReconnect, delay: .milliseconds(50))
        #expect(later.differs(from: live), "the chip shows once the outage has lasted its delay")
        let none = try await draw(nil, delay: .milliseconds(50))
        #expect(!none.differs(from: live), "no connection (a gallery) shows nothing")
    }

    @Test func theChipsDotBreathesOrHoldsStillWithReduceMotion() {
        let early = Date(timeIntervalSinceReferenceDate: 0.35), late = Date(timeIntervalSinceReferenceDate: 1.05)
        #expect(ReconnectingChip.dotOpacity(at: early, reduceMotion: false) != ReconnectingChip.dotOpacity(at: late, reduceMotion: false))
        #expect(ReconnectingChip.dotOpacity(at: early, reduceMotion: true) == 1)
        for date in [early, late] {
            let opacity = ReconnectingChip.dotOpacity(at: date, reduceMotion: false)
            #expect(opacity >= 0.449 && opacity <= 1.001)
        }
    }

    @Test func theChipDraws() throws {
        let image = ImageRenderer(content: ReconnectingChip().padding())
        #expect(image.cgImage != nil)
    }

    // MARK: Placeholder

    @Test func tilesShowTheirNamesAndASoftBarWhileValuesAreOnTheirWay() async throws {
        func draw(pending: Bool) async throws -> NSBitmapImageRep {
            let hosted = HostedWindow(
                GlassTile(title: "Living Room", subtitle: "72°", symbol: "sofa", family: .media, isActive: false) {}
                    .padding()
                    .environment(\.valuesPending, pending)
                    .environment(\.arcSpinnersPaused, true),
                size: CGSize(width: 240, height: 140))
            defer { hosted.close() }
            await hosted.settle(0.5)
            return try #require(hosted.snapshot())
        }
        let value = try await draw(pending: false)
        let bar = try await draw(pending: true)
        #expect(bar.differs(from: value), "the value is a bar until it arrives")
    }
}
}
#endif
