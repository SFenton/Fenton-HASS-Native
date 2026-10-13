import Foundation

/// Something that can call `weather.get_forecasts` and read the data it returns.
///
/// ``HassConnection`` is the app's implementation; tests pass a fake. Mirrors the `callServiceForResponse`
/// path the inventory feature uses, so the weather store opens no second connection.
@MainActor
public protocol WeatherForecastCalling: AnyObject {
    /// Calls `domain.service` with `return_response: true`.
    /// - Returns: The service's `response` object.
    func callServiceForResponse(_ domain: String, _ service: String, data: [String: any Sendable]) async throws -> JSONValue
}

extension HassConnection: WeatherForecastCalling {}

/// Starts and cancels the store's refresh timer; tests drive it by hand.
@MainActor
public protocol WeatherRefreshScheduling: AnyObject {
    /// Runs `action` once after `interval` seconds.
    /// - Returns: A closure that cancels it.
    func schedule(after interval: TimeInterval, _ action: @escaping @MainActor () -> Void) -> @MainActor () -> Void
}

/// The production scheduler, backed by a sleeping `Task`.
@MainActor
public final class WeatherTaskScheduler: WeatherRefreshScheduling {
    public init() {}

    public func schedule(after interval: TimeInterval, _ action: @escaping @MainActor () -> Void) -> @MainActor () -> Void {
        let task = Task { @MainActor in
            try? await Task.sleep(for: .seconds(interval))
            guard !Task.isCancelled else { return }
            action()
        }
        return { task.cancel() }
    }
}
