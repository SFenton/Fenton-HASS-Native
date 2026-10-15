import Foundation
@preconcurrency import HAKit
@preconcurrency import HAKit_Mocks
@testable import HassCore
import os
import Testing

/// The advertisement Home Assistant sent on the home network (Mac, 2026-10-15).
private let homeTXT = [
    "location_name": "Home", "version": "2026.10.1", "uuid": homeID,
    "external_url": "https://homeassistant.sfenton-server.com", "internal_url": "http://192.168.1.22:8123",
    "base_url": "https://homeassistant.sfenton-server.com",
]
private let homeURL = URL(string: "http://192.168.1.22:8123")!
private let homeID = "8086114083f04df5ba46125f69bbdf1f"

/// A route for the home server; pinned to the home instance unless a test is about pinning.
private func makeRoute(finder: FakeFinder, watcher: FakeWatcher = FakeWatcher(local: true),
                       pins: FakePins = FakePins(homeID)) -> LocalServerRoute {
    LocalServerRoute(server: .fentonHome, finder: finder, watcher: watcher, pins: pins)
}

/// Answers with fixed advertisements and a fixed probe result.
private final class FakeFinder: LocalServerFinding, Sendable {
    private let advertisements: [LocalServerAdvertisement]
    private let reachable: Bool
    private let probes = OSAllocatedUnfairLock(initialState: [URL]())
    /// Runs before the finder answers, so a test can change the network mid-check.
    private let beforeAnswer: (@Sendable () -> Void)?

    init(_ advertisements: [LocalServerAdvertisement], reachable: Bool = true, beforeAnswer: (@Sendable () -> Void)? = nil) {
        self.advertisements = advertisements
        self.reachable = reachable
        self.beforeAnswer = beforeAnswer
    }

    var probed: [URL] { probes.withLock { $0 } }

    func firstMatch(timeout: Duration, accept: @escaping @Sendable (LocalServerAdvertisement) -> Bool) async -> LocalServerAdvertisement? {
        beforeAnswer?()
        return advertisements.first(where: accept)
    }

    func answers(_ url: URL, timeout: Duration) async -> Bool {
        probes.withLock { $0.append(url) }
        return reachable
    }
}

/// Pins kept in memory.
private final class FakePins: LocalServerPinStore, Sendable {
    private let pinned: OSAllocatedUnfairLock<String?>

    init(_ pinned: String? = nil) { self.pinned = OSAllocatedUnfairLock(initialState: pinned) }

    var current: String? { pinned.withLock { $0 } }

    func instanceID(for server: HassServer) -> String? { pinned.withLock { $0 } }

    func save(_ instanceID: String, for server: HassServer) { pinned.withLock { $0 = instanceID } }
}

/// Counts how often the route asks whether Home Assistant says the person is home.
private final class HomeCheck: Sendable {
    private let answer: Bool
    private let asks = OSAllocatedUnfairLock(initialState: 0)

    init(_ answer: Bool) { self.answer = answer }

    var count: Int { asks.withLock { $0 } }

    var closure: @Sendable () async -> Bool {
        { [self] in
            asks.withLock { $0 += 1 }
            return answer
        }
    }
}

/// A network path the test sets by hand.
private final class FakeWatcher: NetworkPathWatching, Sendable {
    private let local: OSAllocatedUnfairLock<Bool>
    private let handler = OSAllocatedUnfairLock<(@Sendable () -> Void)?>(initialState: nil)

    init(local: Bool) { self.local = OSAllocatedUnfairLock(initialState: local) }

    var isOnLocalNetwork: Bool { local.withLock { $0 } }

    func start(_ onChange: @escaping @Sendable () -> Void) { handler.withLock { $0 = onChange } }

    /// Moves to another network and reports it.
    func change(local isLocal: Bool) {
        local.withLock { $0 = isLocal }
        handler.withLock { $0 }?()
    }
}

struct LocalServerAdvertisementTests {
    @Test func readsTheTXTRecord() {
        let ad = LocalServerAdvertisement(txt: homeTXT)
        #expect(ad.internalURL == homeURL)
        #expect(ad.instanceID == homeID)
        #expect(ad.externalURL == URL(string: "https://homeassistant.sfenton-server.com"))
        #expect(ad.baseURL == URL(string: "https://homeassistant.sfenton-server.com"))
        #expect(LocalServerAdvertisement(txt: [:]) == LocalServerAdvertisement())
        #expect(LocalServerAdvertisement(txt: ["uuid": ""]).instanceID == nil)
    }

    @Test func pinnedInstance() {
        let home = LocalServerAdvertisement(txt: homeTXT)
        #expect(LocalServerMatch.isPinned(home, to: homeID))
        #expect(LocalServerMatch.isPinned(home, to: nil), "any id before the first time at home")
        var impostor = home
        impostor.instanceID = "0123456789abcdef0123456789abcdef"
        #expect(!LocalServerMatch.isPinned(impostor, to: homeID), "another network posing as home")
        impostor.instanceID = nil
        #expect(!LocalServerMatch.isPinned(impostor, to: nil), "no id, nothing to pin")
    }

    @Test func acceptsOurServersHomeAddress() {
        let ad = LocalServerAdvertisement(txt: homeTXT)
        #expect(LocalServerMatch.localURL(for: .fentonHome, advertisement: ad) == homeURL)
        let onlyBase = LocalServerAdvertisement(internalURL: homeURL, baseURL: HassServer.fentonHome.baseURL)
        #expect(LocalServerMatch.localURL(for: .fentonHome, advertisement: onlyBase) == homeURL, "base_url alone identifies the server")
        let trailingSlash = LocalServerAdvertisement(internalURL: URL(string: "http://192.168.1.22:8123/")!,
                                                     externalURL: URL(string: "https://HomeAssistant.sfenton-server.com:443/")!)
        #expect(LocalServerMatch.localURL(for: .fentonHome, advertisement: trailingSlash) == homeURL)
    }

    @Test func rejectsOtherServersAndPublicAddresses() {
        let otherServer = LocalServerAdvertisement(internalURL: homeURL, externalURL: URL(string: "https://neighbor.example.com"))
        #expect(LocalServerMatch.localURL(for: .fentonHome, advertisement: otherServer) == nil, "someone else's Home Assistant")
        let unnamed = LocalServerAdvertisement(internalURL: homeURL)
        #expect(LocalServerMatch.localURL(for: .fentonHome, advertisement: unnamed) == nil, "no public URL to match")
        let publicHost = LocalServerAdvertisement(internalURL: URL(string: "http://203.0.113.9:8123"), externalURL: HassServer.fentonHome.baseURL)
        #expect(LocalServerMatch.localURL(for: .fentonHome, advertisement: publicHost) == nil, "never send the token to the internet over HTTP")
        let samePublic = LocalServerAdvertisement(internalURL: HassServer.fentonHome.baseURL, externalURL: HassServer.fentonHome.baseURL)
        #expect(LocalServerMatch.localURL(for: .fentonHome, advertisement: samePublic) == nil)
        let ftp = LocalServerAdvertisement(internalURL: URL(string: "ftp://192.168.1.22"), externalURL: HassServer.fentonHome.baseURL)
        #expect(LocalServerMatch.localURL(for: .fentonHome, advertisement: ftp) == nil)
    }

    @Test(arguments: [
        ("192.168.1.22", true), ("10.0.0.5", true), ("172.16.0.1", true), ("172.31.255.1", true), ("169.254.3.4", true),
        ("8086114083f04df5ba46125f69bbdf1f.local", true), ("homeassistant.local", true),
        ("fdd7:1314:8b28:4fa1:5380:572a:6e01:c3cd", true), ("[fe80::5a14:fc6e:64d2:fd91]", true),
        ("172.32.0.1", false), ("172.15.0.1", false), ("8.8.8.8", false), ("2606:4700::6810:c96", false),
        ("homeassistant.sfenton-server.com", false), ("192.168.1", false),
    ])
    func privateHosts(host: String, isPrivate: Bool) {
        #expect(LocalServerMatch.isPrivateHost(host) == isPrivate, "\(host)")
    }

    @Test func launchPolicy() {
        #expect(LocalServerRoute.isEnabled(environment: [:]))
        #expect(!LocalServerRoute.isEnabled(environment: ["FENTON_UITEST_RESET": "1"]))
        #expect(!LocalServerRoute.isEnabled(environment: ["FENTON_HASS_TOKEN": "x"]))
        #expect(!LocalServerRoute.isEnabled(environment: ["FENTON_GALLERY": "media-remote"]))
        #expect(LocalServerRoute.isEnabled(environment: ["FENTON_HASS_TOKEN": "x", "FENTON_LOCAL_ROUTE": "1"]))
        #expect(!LocalServerRoute.isEnabled(environment: ["FENTON_LOCAL_ROUTE": "0"]))
    }
}

struct LocalServerRouteTests {
    @Test func usesTheHomeAddressWhenItAnswers() async {
        let finder = FakeFinder([LocalServerAdvertisement(txt: homeTXT)])
        let route = makeRoute(finder: finder)
        #expect(route.currentURL == HassServer.fentonHome.baseURL, "public URL until a check succeeds")
        #expect(await route.refresh())
        #expect(route.currentURL == homeURL)
        #expect(route.isLocal)
        #expect(finder.probed == [homeURL])
        #expect(await route.refresh() == false, "no change on a second check")
    }

    @Test func staysPublicWhenTheHomeAddressDoesNotAnswer() async {
        let route = makeRoute(finder: FakeFinder([LocalServerAdvertisement(txt: homeTXT)], reachable: false))
        #expect(await route.refresh() == false)
        #expect(route.currentURL == HassServer.fentonHome.baseURL)
    }

    @Test func staysPublicOffWiFi() async {
        let finder = FakeFinder([LocalServerAdvertisement(txt: homeTXT)])
        let route = makeRoute(finder: finder, watcher: FakeWatcher(local: false))
        #expect(await route.refresh() == false)
        #expect(finder.probed.isEmpty, "cellular never looks for the home address")
    }

    @Test func leavingHomeDropsTheHomeAddress() async {
        let watcher = FakeWatcher(local: true)
        let route = makeRoute(finder: FakeFinder([LocalServerAdvertisement(txt: homeTXT)]), watcher: watcher)
        await route.refresh()
        watcher.change(local: false)
        #expect(route.reset())
        #expect(route.currentURL == HassServer.fentonHome.baseURL)
        #expect(await route.refresh() == false)
        #expect(route.reset() == false, "nothing to drop")
    }

    @Test func aCheckFromTheOldNetworkIsIgnored() async {
        let routeBox = OSAllocatedUnfairLock<LocalServerRoute?>(initialState: nil)
        let finder = FakeFinder([LocalServerAdvertisement(txt: homeTXT)]) { routeBox.withLock { $0 }?.reset() }
        let route = makeRoute(finder: finder)
        routeBox.withLock { $0 = route }
        #expect(await route.refresh() == false, "the network changed while the check ran")
        #expect(!route.isLocal)
    }

    @Test func refreshesOnNetworkChange() async {
        let watcher = FakeWatcher(local: true)
        let route = makeRoute(finder: FakeFinder([]), watcher: watcher)
        let calls = OSAllocatedUnfairLock(initialState: 0)
        route.startWatching { calls.withLock { $0 += 1 } }
        watcher.change(local: false)
        watcher.change(local: true)
        #expect(calls.withLock { $0 } == 2)
    }

    @Test func pinsTheServerTheFirstTimeHomeAssistantSaysYouAreHome() async {
        let pins = FakePins()
        let home = HomeCheck(true)
        let route = makeRoute(finder: FakeFinder([LocalServerAdvertisement(txt: homeTXT)]), pins: pins)
        #expect(await route.refresh(confirmHome: home.closure))
        #expect(route.isLocal)
        #expect(pins.current == homeID)
        route.reset()
        #expect(await route.refresh(confirmHome: home.closure))
        #expect(home.count == 1, "once pinned, the advertisement's id is enough")
    }

    @Test func neverPinsWithoutHomeAssistantSayingYouAreHome() async {
        let pins = FakePins()
        let finder = FakeFinder([LocalServerAdvertisement(txt: homeTXT)])
        let route = makeRoute(finder: finder, pins: pins)
        #expect(await route.refresh() == false, "the default never confirms home")
        #expect(await route.refresh(confirmHome: HomeCheck(false).closure) == false)
        #expect(!route.isLocal)
        #expect(pins.current == nil)
        #expect(finder.probed.isEmpty, "the token never goes to an unconfirmed address")
    }

    @Test func ignoresAnImpostorOncePinned() async {
        var impostor = LocalServerAdvertisement(txt: homeTXT)
        impostor.instanceID = "0123456789abcdef0123456789abcdef"
        let finder = FakeFinder([impostor])
        let home = HomeCheck(true)
        let route = makeRoute(finder: finder)
        #expect(await route.refresh(confirmHome: home.closure) == false)
        #expect(!route.isLocal)
        #expect(home.count == 0, "pinned: presence can't override the id")
        #expect(finder.probed.isEmpty)
    }

    @Test func ignoresAnAdvertisementWithoutAnID() async {
        var unnamed = LocalServerAdvertisement(txt: homeTXT)
        unnamed.instanceID = nil
        let pins = FakePins()
        let route = makeRoute(finder: FakeFinder([unnamed]), pins: pins)
        #expect(await route.refresh(confirmHome: HomeCheck(true).closure) == false)
        #expect(pins.current == nil)
    }

    @Test func doesNotPinWhenTheAddressDoesNotAnswer() async {
        let pins = FakePins()
        let route = makeRoute(finder: FakeFinder([LocalServerAdvertisement(txt: homeTXT)], reachable: false), pins: pins)
        #expect(await route.refresh(confirmHome: HomeCheck(true).closure) == false)
        #expect(pins.current == nil)
    }
}

@MainActor
struct HassConnectionRouteTests {
    @Test func connectionInfoFollowsTheRoute() async throws {
        #expect(HassConnection.connectionInfo(server: .fentonHome, route: nil)?.url == HassServer.fentonHome.baseURL)
        let route = makeRoute(finder: FakeFinder([LocalServerAdvertisement(txt: homeTXT)]))
        #expect(HassConnection.connectionInfo(server: .fentonHome, route: route)?.url == HassServer.fentonHome.baseURL)
        await route.refresh()
        let info = try #require(HassConnection.connectionInfo(server: .fentonHome, route: route))
        #expect(info.webSocketURL == URL(string: "http://192.168.1.22:8123/api/websocket"))
    }

    @Test func aFailedSocketFallsBackToThePublicURL() async throws {
        let route = makeRoute(finder: FakeFinder([LocalServerAdvertisement(txt: homeTXT)]))
        await route.refresh()
        let mock = HAMockConnection()
        let cache = EntitySnapshotCache(fileURL: FileManager.default.temporaryDirectory.appending(path: "route-\(UUID()).json"))
        let connection = HassConnection(server: .fentonHome, store: EntityStore(), snapshotCache: cache, connection: mock, route: route)
        // Not waiting for the callback queue: it is the main queue this test runs on.
        mock.setState(.disconnected(reason: .waitingToReconnect(lastError: URLError(.networkConnectionLost), atLatest: Date(), retryCount: 1)),
                      waitForQueue: false)
        for _ in 0..<100 where route.isLocal { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!route.isLocal)
        #expect(connection.status == .waitingToReconnect)
    }

    @Test func leavingTheNetworkDropsTheHomeAddress() async throws {
        let watcher = FakeWatcher(local: true)
        let route = makeRoute(finder: FakeFinder([LocalServerAdvertisement(txt: homeTXT)]), watcher: watcher)
        await route.refresh()
        let mock = HAMockConnection()
        let cache = EntitySnapshotCache(fileURL: FileManager.default.temporaryDirectory.appending(path: "route-\(UUID()).json"))
        let connection = HassConnection(server: .fentonHome, store: EntityStore(), snapshotCache: cache, connection: mock, route: route)
        watcher.change(local: false)
        for _ in 0..<100 where route.isLocal { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!route.isLocal)
        #expect(connection.route === route)
    }

    /// A connection on the public URL whose store holds the signed-in person (user `abc`) in `state`.
    private func presence(_ state: String, freshness: EntityStore.Freshness = .live,
                          userID: String = "abc") -> (HassConnection, HAMockConnection) {
        let route = makeRoute(finder: FakeFinder([]), pins: FakePins())
        let mock = HAMockConnection()
        let cache = EntitySnapshotCache(fileURL: FileManager.default.temporaryDirectory.appending(path: "route-\(UUID()).json"))
        let store = EntityStore()
        let connection = HassConnection(server: .fentonHome, store: store, snapshotCache: cache, connection: mock, route: route)
        store.replaceAll([
            EntityState(entityId: "person.stephen", state: state, attributes: ["user_id": .string(userID)]),
            EntityState(entityId: "person.guest", state: "home", attributes: ["user_id": .string("other")]),
        ], freshness: freshness)
        return (connection, mock)
    }

    /// Answers the `auth/current_user` request with user `abc`.
    private func answerCurrentUser(_ mock: HAMockConnection) async throws {
        for _ in 0..<1_000 where mock.pendingRequests.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        let request = try #require(mock.pendingRequests.first)
        #expect(request.request.type == .currentUser)
        request.completion(.success(HAData(value: ["id": "abc", "name": "Stephen", "is_owner": true, "is_admin": true])))
    }

    @Test func homeIsConfirmedByTheSignedInPersonsLiveState() async throws {
        let (connection, mock) = presence("home")
        async let confirmed = connection.isHomeConfirmedOverPublicURL()
        try await answerCurrentUser(mock)
        #expect(await confirmed)
    }

    @Test func homeIsNotConfirmedAwayOrFromAnotherPerson() async throws {
        let (away, awayMock) = presence("not_home")
        async let awayConfirmed = away.isHomeConfirmedOverPublicURL()
        try await answerCurrentUser(awayMock)
        #expect(await awayConfirmed == false)

        let (someoneElse, otherMock) = presence("home", userID: "xyz")
        async let otherConfirmed = someoneElse.isHomeConfirmedOverPublicURL()
        try await answerCurrentUser(otherMock)
        #expect(await otherConfirmed == false, "only the signed-in person's presence counts")
    }

    @Test func homeIsNotConfirmedFromTheDiskSnapshot() async {
        let (connection, mock) = presence("home", freshness: .snapshot(savedAt: Date()))
        #expect(await connection.isHomeConfirmedOverPublicURL() == false)
        #expect(mock.pendingRequests.isEmpty)
    }
}
