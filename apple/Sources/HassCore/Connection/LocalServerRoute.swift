import Foundation
@preconcurrency import Network
import os

/// Where the websocket opens: Home Assistant's own address on the home network when the phone can reach it there,
/// otherwise the server's public URL.
///
/// At home the public URL still leaves the house through Cloudflare and comes back (40–65 ms a request, measured
/// 2026-10-15), while Home Assistant's home network address answers in about 14 ms. The route finds the server by
/// its zeroconf advertisement (`_home-assistant._tcp`), accepts it only when the advertisement names this server's
/// public URL and points at a private address, and checks that the address answers before using it. Anything
/// else, or any network change, falls back to the public URL. See `.agents/platforms/apple/connection-lifecycle.md`.
public final class LocalServerRoute: Sendable {
    /// Home Assistant's zeroconf service type (listed in `NSBonjourServices`).
    public static let serviceType = "_home-assistant._tcp"
    /// How long to listen for the advertisement.
    static let browseTimeout: Duration = .milliseconds(1500)
    /// How long the home network address has to answer.
    static let probeTimeout: Duration = .milliseconds(1500)

    /// The signed-in server; its ``HassServer/baseURL`` stays the app's identity for caches and links.
    public let server: HassServer

    private let finder: any LocalServerFinding
    private let watcher: any NetworkPathWatching
    private let state = OSAllocatedUnfairLock(initialState: State())

    private struct State {
        var localURL: URL?
        /// Bumped by ``reset()`` so a check that started on the old network can't apply its answer.
        var generation = 0
    }

    /// Creates a route for a server.
    /// - Parameters:
    ///   - server: The signed-in server.
    ///   - finder: Finds and checks the home network address (Bonjour and HTTP in the app, a fake in tests).
    ///   - watcher: Reports network changes.
    public init(server: HassServer, finder: any LocalServerFinding = BonjourLocalServerFinder(),
                watcher: any NetworkPathWatching = SystemNetworkPathWatcher()) {
        self.server = server
        self.finder = finder
        self.watcher = watcher
    }

    /// The URL the websocket and REST requests should use now.
    public var currentURL: URL { state.withLock { $0.localURL } ?? server.baseURL }

    /// Whether the route currently uses the home network address.
    public var isLocal: Bool { state.withLock { $0.localURL != nil } }

    /// Calls `onChange` on every network change (and once when watching starts).
    public func startWatching(_ onChange: @escaping @Sendable () -> Void) {
        watcher.start(onChange)
    }

    /// Looks for the server on the current network and moves the route to its home network address, or back.
    /// - Returns: Whether ``currentURL`` changed.
    @discardableResult
    public func refresh() async -> Bool {
        let generation = state.withLock { $0.generation }
        var next: URL?
        if watcher.isOnLocalNetwork {
            let server = server
            if let candidate = await finder.firstMatch(timeout: Self.browseTimeout, accept: { LocalServerMatch.localURL(for: server, advertisement: $0) }),
               await finder.answers(candidate, timeout: Self.probeTimeout) {
                next = candidate
            }
        }
        // A cancelled check stopped listening early; its empty answer says nothing about the network.
        guard !Task.isCancelled else { return false }
        return state.withLock { state in
            guard state.generation == generation, state.localURL != next else { return false }
            state.localURL = next
            return true
        }
    }

    /// Drops the home network address (the network changed or the socket failed).
    /// - Returns: Whether the route was using it.
    @discardableResult
    public func reset() -> Bool {
        state.withLock { state in
            state.generation += 1
            defer { state.localURL = nil }
            return state.localURL != nil
        }
    }

    /// Whether the app looks for the home network address this launch.
    ///
    /// Off for UI test launches (a reset, a test token or a gallery page) so journeys always use the server they
    /// were given, unless `FENTON_LOCAL_ROUTE=1`; `FENTON_LOCAL_ROUTE=0` turns it off anywhere.
    public static func isEnabled(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        switch environment["FENTON_LOCAL_ROUTE"] {
        case "1": return true
        case "0": return false
        default:
            let testLaunch = ["FENTON_UITEST_RESET", "FENTON_HASS_TOKEN", "FENTON_GALLERY"].contains { environment[$0]?.isEmpty == false }
            return !testLaunch
        }
    }
}

// MARK: - Advertisement

/// Home Assistant's zeroconf advertisement: the URLs in its `_home-assistant._tcp` TXT record.
public struct LocalServerAdvertisement: Equatable, Sendable {
    /// `internal_url`: the address on the home network, e.g. `http://192.168.1.22:8123`.
    public var internalURL: URL?
    /// `external_url`: the public URL.
    public var externalURL: URL?
    /// `base_url`: the URL Home Assistant prefers (public when one is set).
    public var baseURL: URL?

    /// Creates an advertisement.
    public init(internalURL: URL? = nil, externalURL: URL? = nil, baseURL: URL? = nil) {
        self.internalURL = internalURL
        self.externalURL = externalURL
        self.baseURL = baseURL
    }

    /// Reads a TXT record's keys.
    public init(txt: [String: String]) {
        self.init(
            internalURL: txt["internal_url"].flatMap(URL.init(string:)),
            externalURL: txt["external_url"].flatMap(URL.init(string:)),
            baseURL: txt["base_url"].flatMap(URL.init(string:))
        )
    }
}

/// Decides whether an advertisement is the signed-in server's home network address.
public enum LocalServerMatch {
    /// The advertisement's internal URL when it belongs to `server` and points at a private address.
    ///
    /// The bearer token goes to this address over plain HTTP, so it must be advertised by a server that names our
    /// public URL, and it must be a home network address (private IPv4, IPv6 unique-local or link-local, or a
    /// `.local` name), never somewhere on the internet.
    public static func localURL(for server: HassServer, advertisement: LocalServerAdvertisement) -> URL? {
        let claimsServer = [advertisement.externalURL, advertisement.baseURL].contains { $0.map { isSameOrigin($0, server.baseURL) } ?? false }
        guard claimsServer, let url = advertisement.internalURL, let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme), let host = url.host(), isPrivateHost(host),
              !isSameOrigin(url, server.baseURL) else { return nil }
        return HassServer(baseURL: url).baseURL
    }

    /// Same scheme, host and port (default ports filled in).
    static func isSameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
        func origin(_ url: URL) -> String? {
            guard let scheme = url.scheme?.lowercased(), let host = url.host()?.lowercased() else { return nil }
            let port = url.port ?? (scheme == "https" ? 443 : 80)
            return "\(scheme)://\(host):\(port)"
        }
        return origin(lhs) != nil && origin(lhs) == origin(rhs)
    }

    /// A host only reachable on the local network.
    static func isPrivateHost(_ host: String) -> Bool {
        let host = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if host.hasSuffix(".local") { return true }
        if host.contains(":") {
            // IPv6: unique-local fc00::/7 or link-local fe80::/10.
            return host.hasPrefix("fc") || host.hasPrefix("fd") || host.hasPrefix("fe8") || host.hasPrefix("fe9")
                || host.hasPrefix("fea") || host.hasPrefix("feb")
        }
        let octets = host.split(separator: ".").compactMap { UInt8($0) }
        guard octets.count == 4 else { return false }
        switch (octets[0], octets[1]) {
        case (10, _), (192, 168), (169, 254): return true
        case let (172, second): return (16...31).contains(second)
        default: return false
        }
    }
}

// MARK: - Seams

/// Finds Home Assistant on the current network and checks an address answers.
public protocol LocalServerFinding: Sendable {
    /// Listens for advertisements for up to `timeout`, returning the first URL `accept` gives.
    func firstMatch(timeout: Duration, accept: @escaping @Sendable (LocalServerAdvertisement) -> URL?) async -> URL?
    /// Whether `url` answers as Home Assistant within `timeout`.
    func answers(_ url: URL, timeout: Duration) async -> Bool
}

/// Reports whether the phone is on a local network (Wi-Fi or Ethernet) and when that changes.
public protocol NetworkPathWatching: Sendable {
    /// The current path uses Wi-Fi or Ethernet.
    var isOnLocalNetwork: Bool { get }
    /// Starts watching; `onChange` runs on every path update.
    func start(_ onChange: @escaping @Sendable () -> Void)
}

// MARK: - System implementations

/// Browses `_home-assistant._tcp` with Bonjour and checks addresses with `GET /manifest.json`.
public struct BonjourLocalServerFinder: LocalServerFinding {
    private static let queue = DispatchQueue(label: "com.sfenton.home.local-server")
    private let session: URLSession

    /// Creates a finder.
    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    public func firstMatch(timeout: Duration, accept: @escaping @Sendable (LocalServerAdvertisement) -> URL?) async -> URL? {
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: LocalServerRoute.serviceType, domain: nil), using: .tcp)
        let found = OSAllocatedUnfairLock<URL?>(initialState: nil)
        browser.browseResultsChangedHandler = { results, _ in
            for result in results {
                guard case let .bonjour(record) = result.metadata,
                      let url = accept(LocalServerAdvertisement(txt: record.dictionary)) else { continue }
                found.withLock { $0 = $0 ?? url }
            }
        }
        browser.start(queue: Self.queue)
        defer { browser.cancel() }
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline, !Task.isCancelled {
            if let url = found.withLock({ $0 }) { return url }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return found.withLock { $0 }
    }

    public func answers(_ url: URL, timeout: Duration) async -> Bool {
        var request = URLRequest(url: url.appending(path: "manifest.json"))
        let (seconds, attoseconds) = timeout.components
        request.timeoutInterval = Double(seconds) + Double(attoseconds) / 1e18
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (_, response) = try? await session.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }
}

/// Watches the network path with `NWPathMonitor`.
public final class SystemNetworkPathWatcher: NetworkPathWatching, @unchecked Sendable {
    // Unchecked: `monitor` is configured once in `start` and only touched again by `deinit`.
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.sfenton.home.network-path")
    private let local = OSAllocatedUnfairLock(initialState: false)

    /// Creates a watcher; nothing happens until ``start(_:)``.
    public init() {}

    deinit { monitor.cancel() }

    public var isOnLocalNetwork: Bool { local.withLock { $0 } }

    public func start(_ onChange: @escaping @Sendable () -> Void) {
        monitor.pathUpdateHandler = { [local] path in
            let isLocal = path.status == .satisfied && (path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet))
            local.withLock { $0 = isLocal }
            onChange()
        }
        monitor.start(queue: queue)
    }
}
