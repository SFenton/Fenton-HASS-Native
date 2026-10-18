@testable import HassDesign
import SwiftUI
import Testing

/// The state colour helpers and ``MotionAudit`` (design: `.agents/design/motion-components.md`, "How it is validated").
@MainActor
struct StateColorTransitionTests {
    /// The components a render drew a state animation for. The view is built inside the capture, because some helpers note
    /// themselves when the view is made rather than when its body runs.
    static func audit<V: View>(_ view: @autoclosure () -> V, width: CGFloat = 402) -> Set<String> {
        MotionAudit.capture { _ = ImageRenderer(content: view().frame(width: width)).cgImage }
    }

    @Test func eachHelperRecordsItsComponent() {
        let layer = Color.red.frame(width: 40, height: 40)
        #expect(Self.audit(layer.stateColorTransition("A", value: 1)) == ["A"])
        #expect(Self.audit(layer.stateColor("B") { $0.foregroundStyle(Color.blue) }) == ["B"])
        #expect(Self.audit(layer.stateForeground("C", Color.green)) == ["C"])
        #expect(Self.audit(layer.quickTransition("D", value: true)) == ["D"])
        #expect(Self.audit(layer.quickTransition("E", value: true, instant: true)) == ["E"])
    }

    @Test func aViewWithoutAHelperRecordsNothing() {
        #expect(Self.audit(Color.red.frame(width: 40, height: 40)).isEmpty)
    }

    @Test func enableCollectsComponentsAcrossRenders() {
        MotionAudit.enable()
        _ = Self.audit(Color.red.stateColorTransition("Enabled-\(#line)", value: 0))
        #expect(MotionAudit.components.contains { $0.hasPrefix("Enabled-") })
    }

    @Test func rendersAcrossValueChanges() {
        for value in [0, 1] {
            #expect(ImageRenderer(content: Color.red.frame(width: 20, height: 20).stateColorTransition("R", value: value)).cgImage != nil)
        }
    }
}
