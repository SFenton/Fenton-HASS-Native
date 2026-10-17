@testable import HassDesign
import Testing

struct PerfSwitchesTests {
    @Test func parsesTheNamedLayersAndIgnoresTheRest() {
        #expect(PerfSwitches.parse("headerFade,backdrop") == [.headerFade, .backdrop])
        #expect(PerfSwitches.parse(" backdrop , nonsense,") == [.backdrop])
        #expect(PerfSwitches.parse("") == [])
        #expect(PerfSwitches.parse(nil) == [])
    }

    @Test func aNormalLaunchHasEveryLayerOn() {
        #expect(!PerfSwitches.isOff(.headerFade))
        #expect(!PerfSwitches.isOff(.backdrop))
    }
}
