import Foundation
@preconcurrency import HAKit

// MARK: - Raw websocket commands

extension HassConnection {
    /// Sends a websocket command once and returns HAKit's raw result. It never retries across reconnects, so a
    /// mutation is never applied twice. Every one-off command (service responses, schedules, todo lists, the
    /// service catalog, signed paths) goes through here rather than its own continuation bridge.
    func sendCommand(_ command: String, data: [String: any Sendable]) async throws -> HAData {
        let request = HARequest(type: .webSocket(command), data: data, shouldRetry: false)
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<HAData, Error>) in
            connection.send(request) { result in
                switch result {
                case let .success(value): continuation.resume(returning: value)
                case let .failure(error): continuation.resume(throwing: error)
                }
            }
        }
    }

    /// ``sendCommand(_:data:)`` with the whole result as JSON.
    func requestJSON(_ command: String, data: [String: any Sendable]) async throws -> JSONValue {
        JSONValue(haData: try await sendCommand(command, data: data))
    }

    /// `call_service` with `return_response: true`, as the whole result (`{"response": ...}` from Home Assistant).
    func callServiceReturningResult(_ domain: String, _ service: String, data: [String: any Sendable]) async throws -> JSONValue {
        try await requestJSON("call_service", data: ["domain": domain, "service": service, "service_data": data, "return_response": true])
    }
}
