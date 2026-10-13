import Foundation
@preconcurrency import HAKit

/// Reads which services Home Assistant offers, so commands that need an installed script or integration
/// service can be disabled when it is missing (web `hassServiceAvailable`).
@MainActor
public protocol HassServiceCatalog: AnyObject {
    /// Every `domain.service` name.
    func serviceNames() async throws -> Set<String>
}

extension HassConnection: HassServiceCatalog {
    /// Every `domain.service` name (`get_services`).
    public func serviceNames() async throws -> Set<String> {
        let request = HARequest(type: .webSocket("get_services"), data: [:], shouldRetry: false)
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Set<String>, Error>) in
            connection.send(request) { result in
                switch result {
                case let .success(.dictionary(domains)):
                    continuation.resume(returning: HassServices.names(domains))
                case .success:
                    continuation.resume(throwing: UnexpectedResponse(command: "get_services"))
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

/// Pure helpers for the service catalog.
public enum HassServices {
    /// Flattens a `get_services` result (`{domain: {service: {...}}}`) into `domain.service` names.
    public static func names(_ domains: [String: Any]) -> Set<String> {
        var names: Set<String> = []
        for (domain, services) in domains {
            guard let services = services as? [String: Any] else { continue }
            for service in services.keys { names.insert("\(domain).\(service)") }
        }
        return names
    }
}
