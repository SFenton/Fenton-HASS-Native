import Foundation
@preconcurrency import HAKit
@preconcurrency import HAKit_Mocks
@testable import HassCore
import Testing

/// The socket checks the camera streams rely on after a background (owner report 2026-10-16: HAKit drops a
/// command caught by a reset without answering it, so streams requested then never came back).
@MainActor
struct HassConnectionLivenessTests {
    private func makeConnection() -> (HassConnection, HAMockConnection) {
        let mock = HAMockConnection()
        let cache = EntitySnapshotCache(fileURL: FileManager.default.temporaryDirectory.appending(path: "liveness-\(UUID()).json"))
        let connection = HassConnection(server: .fentonHome, store: EntityStore(), snapshotCache: cache, connection: mock)
        return (connection, mock)
    }

    private func settle(_ mock: HAMockConnection) async {
        // The mock delivers state changes on the main queue; yield so they land (its own wait spins a run loop, which hangs here).
        try? await Task.sleep(for: .milliseconds(50))
    }

    private func pendingPing(_ mock: HAMockConnection) async throws -> HAMockConnection.PendingRequest {
        for _ in 0..<500 where !mock.pendingRequests.contains(where: { $0.request.type == .ping }) {
            try? await Task.sleep(for: .milliseconds(10))
        }
        return try #require(mock.pendingRequests.first { $0.request.type == .ping })
    }

    // MARK: - Commands that are never answered

    @Test func aCommandHAKitNeverAnswersTimesOut() async throws {
        let (connection, mock) = makeConnection()
        await #expect(throws: CommandTimeout.self) {
            _ = try await connection.sendCommand("auth/sign_path", data: [:], timeout: .milliseconds(80))
        }
        #expect(mock.cancelledRequests.count == 1, "The dropped request is cancelled so HAKit does not resend it")
    }

    @Test func aCommandAnsweredInTimeReturnsItsResultOnce() async throws {
        let (connection, mock) = makeConnection()
        let task = Task { try await connection.sendCommand("auth/sign_path", data: [:], timeout: .milliseconds(200)) }
        for _ in 0..<500 where mock.pendingRequests.isEmpty { try? await Task.sleep(for: .milliseconds(10)) }
        let request = try #require(mock.pendingRequests.first)
        request.completion(.success(HAData(value: ["path": "/api/webrtc/ws?authSig=x"])))
        _ = try await task.value
        try? await Task.sleep(for: .milliseconds(300)) // The timer fires later and must not resume again.
        #expect(mock.cancelledRequests.isEmpty)
    }

    @Test func streamCommandsCarryATimeout() {
        #expect(HassConnection.streamCommandTimeout > .seconds(5))
    }

    // MARK: - Waiting for the socket

    @Test func awaitConnectedReturnsOnceTheSocketIsReady() async throws {
        let (connection, mock) = makeConnection()
        connection.connect(subscribingToStates: false)
        await settle(mock)
        #expect(await connection.awaitConnected(timeout: .seconds(1)))
        if case .connected = connection.status {} else { Issue.record("Expected connected, got \(connection.status)") }
    }

    @Test func awaitConnectedGivesUpOnTimeoutAndWhenRejected() async {
        let (connection, mock) = makeConnection()
        #expect(await connection.awaitConnected(timeout: .milliseconds(150)) == false, "Never connected")
        mock.setState(.disconnected(reason: .rejected), waitForQueue: false)
        await settle(mock)
        #expect(await connection.awaitConnected(timeout: .seconds(2)) == false, "A rejected token stops the wait at once")
    }

    @Test func readyNotificationPostsEachTimeTheSocketBecomesReady() async {
        let (connection, mock) = makeConnection()
        var count = 0
        let token = NotificationCenter.default.addObserver(forName: HassConnection.didBecomeReadyNotification, object: connection, queue: .main) { _ in
            MainActor.assumeIsolated { count += 1 }
        }
        defer { NotificationCenter.default.removeObserver(token) }
        /// HAKit calls back on the connection's own queue, so each state reaches the main actor a hop after it is set; wait for
        /// the connection to show it instead of guessing how long the hop takes.
        func waitFor(_ condition: () -> Bool) async {
            for _ in 0..<300 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
        }
        func isConnected() -> Bool {
            if case .connected = connection.status { return true }
            return false
        }
        connection.connect(subscribingToStates: false)
        await waitFor(isConnected)
        mock.setState(.disconnected(reason: .disconnected), waitForQueue: false)
        await waitFor { connection.status == .disconnected }
        mock.setState(.ready(version: "1.0-mock"), waitForQueue: false)
        await waitFor(isConnected)
        await settle(mock)
        #expect(count == 2, "First connect and the reconnect")
    }

    // MARK: - Making the socket answer

    @Test func aSocketThatAnswersIsLeftAlone() async throws {
        let (connection, mock) = makeConnection()
        connection.connect(subscribingToStates: false)
        await settle(mock)
        async let live = connection.ensureLive(timeout: .seconds(2), pingTimeout: .seconds(1))
        try await pendingPing(mock).completion(.success(.empty))
        #expect(await live)
        #expect(mock.cancelledRequests.isEmpty)
        if case .connected = connection.status {} else { Issue.record("Expected connected, got \(connection.status)") }
    }

    @Test func aSocketThatDoesNotAnswerIsReplaced() async throws {
        let (connection, mock) = makeConnection()
        var transitions = 0
        let token = NotificationCenter.default.addObserver(forName: HAConnectionState.didTransitionToStateNotification, object: mock, queue: .main) { _ in
            MainActor.assumeIsolated { transitions += 1 }
        }
        defer { NotificationCenter.default.removeObserver(token) }
        connection.connect(subscribingToStates: false)
        await settle(mock)
        let before = transitions
        let live = await connection.ensureLive(timeout: .seconds(3), pingTimeout: .milliseconds(100))
        #expect(live, "The replacement socket is ready")
        await settle(mock)
        // The mock collapses the reconnect into its final state, so count its transitions: disconnected, connecting,
        // authenticating, ready.
        #expect(transitions - before == 4, "The silent socket was disconnected and connected again")
        if case .ready = mock.state {} else { Issue.record("Expected ready, got \(mock.state)") }
    }

    @Test func aDisconnectedAppIsNotReconnectedByTheCheck() async {
        let (connection, _) = makeConnection()
        #expect(await connection.ensureLive(timeout: .milliseconds(200)) == false)
        connection.reconnect()
        #expect(connection.status == .disconnected, "Only a connection the app wants is replaced")
    }
}
