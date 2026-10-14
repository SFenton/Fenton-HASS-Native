import Foundation
import Observation
#if os(iOS)
import UIKit
#endif

/// Reports this phone's location to Home Assistant through `mobile_app` (`.agents/platforms/apple/location.md`).
///
/// - Permission: While Using the App first, then the upgrade to Always, with Precise Location.
/// - With Always and Precise: watches the nearest zones (``ZonePlanner``) and significant changes, and sends the
///   zone result with each crossing (``ZoneEventResolver``). With While Using only: a fix on each app open.
/// - Every fix passes ``LocationFixFilter`` first.
/// - iPads are not presence devices by default (``isPresenceDevice``): one left at home and tied to a person would
///   mark them home while they are away. A non-presence device never reports location.
///
/// Not started by the app yet (plan Phase 2 wires it after the shared registration lands); only the debug gallery
/// and tests drive it.
@MainActor
@Observable
public final class LocationReporter {
    /// The current permission, kept in step with the platform.
    public private(set) var permission: LocationPermission
    /// Whether reporting is on.
    public private(set) var isRunning = false
    /// The regions being watched.
    public private(set) var monitoredRegions: [PlannedRegion] = []
    /// Why the last update was sent (the Last Update Trigger sensor's state).
    public private(set) var lastTrigger: LocationTrigger?
    /// When the last update was accepted by Home Assistant.
    public private(set) var lastReportDate: Date?
    /// The last webhook failure; cleared by the next success.
    public private(set) var lastError: MobileAppWebhookError?
    /// Whether this device reports location at all.
    public let isPresenceDevice: Bool

    @ObservationIgnored private let platform: any LocationPlatform
    @ObservationIgnored private let client: MobileAppWebhookClient
    @ObservationIgnored private let batteryLevel: @MainActor () -> Int?
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private var filter = LocationFixFilter()
    @ObservationIgnored private var zones: [HAZone] = []
    @ObservationIgnored private var lastFix: LocationFix?

    /// Creates a reporter.
    /// - Parameters:
    ///   - platform: Core Location, or a fake in tests.
    ///   - client: Sends the webhook commands.
    ///   - isPresenceDevice: Whether this device reports location; defaults to false on iPad.
    ///   - batteryLevel: The battery percentage sent with each update.
    ///   - now: The clock, for ``lastReportDate``.
    public init(platform: any LocationPlatform, client: MobileAppWebhookClient,
                isPresenceDevice: Bool = LocationReporter.deviceIsPresenceDevice,
                batteryLevel: @escaping @MainActor () -> Int? = { nil }, now: @escaping @MainActor () -> Date = Date.init) {
        self.platform = platform
        self.client = client
        self.isPresenceDevice = isPresenceDevice
        self.batteryLevel = batteryLevel
        self.now = now
        permission = platform.permission
        platform.onEvent = { [weak self] event in
            guard let self else { return }
            Task { await self.handle(event) }
        }
    }

    // MARK: - Presence devices

    /// Whether a device of this kind reports location by default: phones do, iPads don't.
    public nonisolated static func isPresenceDevice(isPad: Bool) -> Bool { !isPad }

    /// Whether this device reports location by default.
    public static var deviceIsPresenceDevice: Bool {
        #if os(iOS)
        isPresenceDevice(isPad: UIDevice.current.userInterfaceIdiom == .pad)
        #else
        false
        #endif
    }

    // MARK: - Permission

    /// Asks for the next permission step: While Using the App, then Always. Other states need Settings.
    public func requestPermission() {
        switch permission.authorization {
        case .notDetermined: platform.requestWhenInUse()
        case .whenInUse: platform.requestAlways()
        case .always, .denied, .restricted: break
        }
    }

    // MARK: - Running

    /// Starts reporting: zones, significant changes and a fix for the app opening. Does nothing on a non-presence
    /// device, without permission, or when already running.
    public func start() async {
        guard isPresenceDevice, permission.isAuthorized, !isRunning else { return }
        isRunning = true
        if permission.allowsBackgroundReporting { platform.startSignificantChanges() }
        await refreshZones()
        await report(.launch)
    }

    /// Stops reporting and forgets the fix history (sign-out, permission withdrawn, registration gone).
    public func stop() async {
        guard isRunning else { return }
        isRunning = false
        platform.stopSignificantChanges()
        await platform.stopMonitoring()
        monitoredRegions = []
        filter.reset()
        lastFix = nil
    }

    /// Reads the zones again and re-plans the watched regions.
    public func refreshZones() async {
        guard isRunning else { return }
        do {
            zones = try await client.zones()
        } catch {
            await record(error)
            return
        }
        await replan()
    }

    /// Takes a fix and sends it.
    /// - Returns: Whether Home Assistant accepted an update.
    @discardableResult
    public func report(_ trigger: LocationTrigger) async -> Bool {
        guard isRunning, let fix = try? await platform.currentFix() else { return false }
        return await send(fix, trigger: trigger, locationName: nil)
    }

    // MARK: - Events

    func handle(_ event: LocationPlatformEvent) async {
        switch event {
        case .permissionChanged(let new):
            let old = permission
            permission = new
            guard isRunning else { return }
            if !new.isAuthorized {
                await stop()
            } else if new.allowsBackgroundReporting != old.allowsBackgroundReporting {
                if new.allowsBackgroundReporting { platform.startSignificantChanges() } else { platform.stopSignificantChanges() }
                await replan()
            }
        case .significantChange(let fix):
            guard isRunning else { return }
            await send(fix, trigger: .significantLocationChange, locationName: nil)
            // The nearest zones change as the phone moves.
            await replan()
        case .zone(let zoneEvent):
            guard isRunning else { return }
            let fix = try? await platform.currentFix()
            let name = ZoneEventResolver(zones: zones).locationName(for: zoneEvent, fix: fix)
            guard let sent = fix ?? zoneCenter(for: zoneEvent) else { return }
            await send(sent, trigger: zoneEvent.trigger, locationName: name)
        }
    }

    /// Without a fresh fix, an entry still reports the zone's center at its radius' accuracy, so the crossing
    /// reaches Home Assistant; an exit without a fix says nothing (the next significant change catches it).
    private func zoneCenter(for event: ZoneEvent) -> LocationFix? {
        guard case .entered(let id) = event, let zone = zones.first(where: { $0.entityID == id }) else { return nil }
        return LocationFix(latitude: zone.latitude, longitude: zone.longitude, horizontalAccuracy: zone.radius, timestamp: now())
    }

    // MARK: - Sending

    private func replan() async {
        let plan = permission.allowsBackgroundReporting ? ZonePlanner().plan(zones, near: lastFix) : []
        guard isRunning, plan != monitoredRegions else { return }
        monitoredRegions = plan
        if plan.isEmpty {
            await platform.stopMonitoring()
        } else {
            await platform.monitor(plan)
        }
    }

    @discardableResult
    private func send(_ fix: LocationFix, trigger: LocationTrigger, locationName: String?) async -> Bool {
        // Admit on a copy: a fix that fails to send must not count as the last one sent.
        var candidate = filter
        guard candidate.admit(fix, trigger: trigger),
              let report = LocationReport(fix: fix, batteryLevel: batteryLevel(), locationName: locationName)
        else { return false }
        lastFix = fix
        do {
            try await client.updateLocation(report)
        } catch {
            await record(error)
            return false
        }
        filter = candidate
        lastTrigger = trigger
        lastReportDate = now()
        lastError = nil
        return true
    }

    private func record(_ error: any Error) async {
        guard !(error is CancellationError) else { return }
        let failure = error as? MobileAppWebhookError ?? .network
        lastError = failure
        // Nothing to send to until the phone registers again.
        if failure == .registrationGone || failure == .notRegistered { await stop() }
    }
}
