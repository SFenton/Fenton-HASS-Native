import Foundation
@preconcurrency import HAKit

/// A service caller that can also read a service's response (`return_response`). The wake light and Household
/// Away commands answer with an outcome the app must check before trusting a change.
@MainActor
public protocol HassServiceResponding: HassServiceCalling {
    /// Calls `domain.service` with `return_response` and returns the service's response object.
    func callServiceWithResponse(_ domain: String, _ service: String, data: [String: any Sendable]) async throws -> JSONValue
}

extension HassConnection: HassServiceResponding {
    /// Sends `call_service` with `return_response: true` once (no retry across reconnects, so a command is never
    /// applied twice) and returns the `response` member of the result.
    public func callServiceWithResponse(_ domain: String, _ service: String, data: [String: any Sendable]) async throws -> JSONValue {
        let request = HARequest(
            type: .webSocket("call_service"),
            data: ["domain": domain, "service": service, "service_data": data, "return_response": true],
            shouldRetry: false
        )
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<JSONValue, Error>) in
            connection.send(request) { result in
                switch result {
                case let .success(data): continuation.resume(returning: JSONValue(haData: data))
                case let .failure(error): continuation.resume(throwing: error)
                }
            }
        }
    }
}

extension JSONValue {
    /// Converts a HAKit result.
    init(haData: HAData) {
        switch haData {
        case let .dictionary(values): self = JSONValue(any: values)
        case let .array(values): self = .array(values.map(JSONValue.init(haData:)))
        case let .primitive(value): self = JSONValue(any: value)
        case .empty: self = .null
        }
    }

    /// A command result's response object: `response` when the result wraps it, else the result itself.
    var commandResponse: JSONValue? {
        if case .object? = self["response"] { return self["response"] }
        if case .object = self { return self }
        return nil
    }
}

/// What a response-checked command came back with (web `useWakeLightController` `send`,
/// `useHouseholdAwayController` `send`).
public enum CommandOutcome: Equatable, Sendable {
    /// Applied, or already true (`no_change`).
    case accepted(noChange: Bool, revision: Int?)
    /// Refused with an error code; `alarmConflict` asks the editor to reload the alarm.
    case rejected(code: String, alarmConflict: Bool, revision: Int?)

    /// Reads a response object; `nil` when it carries no outcome (treated as a transport failure).
    public init?(response: JSONValue?) {
        guard let response = response?.commandResponse,
              let outcome = (response["outcome"] ?? response["status"])?.string else { return nil }
        let revision = response["revision"]?.number.map { Int($0) }
        switch outcome {
        case "accepted": self = .accepted(noChange: false, revision: revision)
        case "no_change": self = .accepted(noChange: true, revision: revision)
        default:
            let code = (response["error_code"] ?? response["error"])?.string ?? outcome
            self = .rejected(code: code, alarmConflict: response["conflict"]?.string == "alarm_revision", revision: revision)
        }
    }

    public var isAccepted: Bool { if case .accepted = self { true } else { false } }
}
