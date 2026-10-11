import Foundation
@preconcurrency import HAKit

/// Something that can call a Home Assistant service and read the data it returns (`return_response`).
///
/// EverShelf's inventory, barcode and expiry services answer with data (`SupportsResponse.OPTIONAL` or
/// `.ONLY`), so the inventory feature talks through this instead of ``HassServiceCalling`` alone.
@MainActor
public protocol HassServiceResponding: HassServiceCalling {
    /// Calls `domain.service` with `return_response: true`.
    /// - Returns: The service's `response` object, or ``JSONValue/null`` when it returned nothing.
    func callServiceForResponse(_ domain: String, _ service: String, data: [String: any Sendable]) async throws -> JSONValue
}

extension HassConnection: HassServiceResponding {
    /// Sends `call_service` with `return_response: true` over the app's websocket, once (no retry across
    /// reconnects, so a mutation is never applied twice).
    public func callServiceForResponse(_ domain: String, _ service: String, data: [String: any Sendable]) async throws -> JSONValue {
        let request = HARequest(
            type: .webSocket("call_service"),
            data: ["domain": domain, "service": service, "service_data": data, "return_response": true],
            shouldRetry: false
        )
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<JSONValue, Error>) in
            connection.send(request) { result in
                switch result {
                case let .success(.dictionary(values)): continuation.resume(returning: JSONValue(any: values["response"]))
                case .success: continuation.resume(returning: .null)
                case let .failure(error): continuation.resume(throwing: error)
                }
            }
        }
    }
}

/// User-facing text for a failed service call.
public enum ServiceErrorText {
    /// Home Assistant's own message for a rejected call (e.g. `EverShelf: inventory list failed`), else `fallback`.
    public static func message(for error: Error, fallback: String) -> String {
        if let error = error as? HAError {
            switch error {
            case let .external(external) where !external.message.isEmpty: return external.message
            case let .internal(debugDescription) where !debugDescription.isEmpty: return debugDescription
            default: return fallback
            }
        }
        if let error = error as? LocalizedError, let description = error.errorDescription, !description.isEmpty {
            return description
        }
        return fallback
    }
}
