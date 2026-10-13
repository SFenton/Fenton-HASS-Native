import Foundation
import Observation

// `HassServiceResponding` and `HassConnection.callServiceWithResponse` live in `Bedroom/ServiceResponses.swift`;
// the connection returns the whole result, so ``HouseholdAwayController/outcome(from:)`` unwraps `response`.

/// Sends Household Away commands and reads the status sensor (web `useHouseholdAwayController.ts`).
///
/// Exactly one plan exists, so there is no per-item queue: one command at a time, checked against the
/// script's response, with a timeout that reports an unknown outcome instead of guessing.
@MainActor
@Observable
public final class HouseholdAwayController {
    // MARK: - Types

    /// How a command ended.
    public enum Outcome: Equatable, Sendable {
        /// The script accepted it (or found nothing to change).
        case accepted(revision: Int?)
        /// The script, the connection or the app refused it.
        case rejected(errorCode: String)
        /// No answer in time; the plan may or may not have changed.
        case unknown
    }

    /// Error codes the app raises itself.
    public enum ErrorCode {
        public static let transport = "transport"
        public static let unavailable = "unavailable"
        public static let unknownOutcome = "unknown_outcome"
    }

    // MARK: - State

    /// Live state.
    public let store: EntityStore
    /// A command is in flight.
    public private(set) var pending = false
    /// The last command's error, until cleared or the next command starts.
    public private(set) var errorCode: String?

    @ObservationIgnored private let responder: any HassServiceResponding
    @ObservationIgnored private let timeout: Duration
    @ObservationIgnored private let makeRequestId: @Sendable () -> String
    @ObservationIgnored private var revisionFloor = 0

    /// How long a command may take before its outcome is unknown (web `COMMAND_TIMEOUT_MS`).
    public nonisolated static let commandTimeout: Duration = .seconds(10)

    // MARK: - Init

    /// Creates a controller.
    /// - Parameters:
    ///   - store: Live state.
    ///   - responder: Where commands go: the connection in the app, a script in tests.
    ///   - timeout: Command timeout.
    ///   - makeRequestId: Request ids (tests pass a fixed one).
    public init(
        store: EntityStore,
        responder: any HassServiceResponding,
        timeout: Duration = HouseholdAwayController.commandTimeout,
        makeRequestId: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() }
    ) {
        self.store = store
        self.responder = responder
        self.timeout = timeout
        self.makeRequestId = makeRequestId
    }

    /// The parsed status sensor; observing it observes only that entity.
    public var snapshot: HouseholdAway.Snapshot {
        HouseholdAway.Snapshot(entity: store.entity(HouseholdAway.statusEntityId).state)
    }

    // MARK: - Commands

    /// Clears the shown error.
    public func clearError() { errorCode = nil }

    /// Sends one command.
    @discardableResult
    public func send(_ command: HouseholdAway.Command) async -> Outcome {
        guard !pending else { return .rejected(errorCode: ErrorCode.transport) }
        let current = snapshot
        guard current.canCommand else {
            errorCode = ErrorCode.unavailable
            return .rejected(errorCode: ErrorCode.unavailable)
        }
        pending = true
        errorCode = nil
        defer { pending = false }
        revisionFloor = max(revisionFloor, current.revision)
        let data = HouseholdAway.serviceData(for: command, expectedRevision: revisionFloor, requestId: makeRequestId())
        guard let result = await callWithTimeout(data.mapValues(\.foundationValue)) else {
            errorCode = ErrorCode.unknownOutcome
            return .unknown
        }
        let outcome = Self.outcome(from: result)
        switch outcome {
        case let .accepted(revision): if let revision { revisionFloor = max(revisionFloor, revision) }
        case let .rejected(code): errorCode = code
        case .unknown: break
        }
        return outcome
    }

    /// Reads the script's response (web `responseFrom` and the outcome branch of `send`).
    static func outcome(from result: Result<JSONValue, any Error>) -> Outcome {
        guard case let .success(value) = result else { return .rejected(errorCode: ErrorCode.transport) }
        let response = value["response"].flatMap { $0.isObject ? $0 : nil } ?? value
        guard let status = response["status"]?.string ?? response["outcome"]?.string else {
            return .rejected(errorCode: ErrorCode.transport)
        }
        if status == "accepted" || status == "no_change" {
            let revision = response["revision"]?.number.flatMap { $0 == $0.rounded() ? Int($0) : nil }
            return .accepted(revision: revision)
        }
        return .rejected(errorCode: response["error_code"]?.string ?? response["error"]?.string ?? status)
    }

    /// Calls the script, or returns `nil` once ``timeout`` passes first. The call itself can't be cancelled,
    /// so a late answer is dropped.
    private func callWithTimeout(_ data: [String: any Sendable]) async -> Result<JSONValue, any Error>? {
        let gate = ResumeGate()
        return await withCheckedContinuation { (continuation: CheckedContinuation<Result<JSONValue, any Error>?, Never>) in
            Task { @MainActor [self] in
                let result: Result<JSONValue, any Error>
                do {
                    result = .success(try await responder.callServiceWithResponse(HouseholdAway.commandDomain, HouseholdAway.commandService, data: data))
                } catch {
                    result = .failure(error)
                }
                if gate.claim() { continuation.resume(returning: result) }
            }
            Task { @MainActor [timeout] in
                try? await Task.sleep(for: timeout)
                if gate.claim() { continuation.resume(returning: nil) }
            }
        }
    }

    // MARK: - Convenience

    @discardableResult
    public func cancel() async -> Outcome { await send(.cancel) }
    @discardableResult
    public func endNow() async -> Outcome { await send(.endNow) }
    @discardableResult
    public func resolveRestore(_ action: HouseholdAway.ResolveAction) async -> Outcome { await send(.resolveRestore(action)) }
    @discardableResult
    public func scheduleSoloTrip(traveler: HouseholdResident, draft: SoloTripDraft) async -> Outcome {
        await send(.scheduleSoloTrip(traveler: traveler, start: draft.start, end: draft.end))
    }
    @discardableResult
    public func updateEnd(_ end: WallClock) async -> Outcome { await send(.updateEnd(end)) }
}

/// Lets exactly one of two racing tasks resume a continuation.
@MainActor
private final class ResumeGate {
    private var claimed = false
    func claim() -> Bool {
        guard !claimed else { return false }
        claimed = true
        return true
    }
}

extension JSONValue {
    /// Whether this is an object.
    var isObject: Bool { if case .object = self { true } else { false } }
}
