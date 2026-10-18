import Foundation
@testable import HassCore
import Testing

/// When the "Reconnecting…" chip counts the connection as down.
struct ReconnectingPolicyTests {
    @Test func everyStateThatIsNotLiveOrRefusedIsDown() {
        #expect(!ReconnectingPolicy.isDown(.connected(version: "2026.10")))
        #expect(!ReconnectingPolicy.isDown(.rejected), "a refused token ends the session; no chip")
        #expect(ReconnectingPolicy.isDown(.disconnected))
        #expect(ReconnectingPolicy.isDown(.connecting))
        #expect(ReconnectingPolicy.isDown(.waitingToReconnect))
    }

    @Test func theChipWaitsTwoSeconds() {
        #expect(ReconnectingPolicy.delay == .seconds(2))
    }
}
