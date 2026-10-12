@testable import HassDesign
import Testing

struct SymbolMapTests {
    @Test func mapsKnownIconsAndFallsBackToACircle() {
        #expect(SymbolMap.symbol(for: "mdi:robot-vacuum") != "circle")
        #expect(SymbolMap.symbol(for: "mdi:not-a-real-icon") == "circle")
    }
}
