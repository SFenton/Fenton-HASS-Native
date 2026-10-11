import SwiftUI

/// Observes iPhone Duo signals (hinge and vertical bar) and records them in ``HingePresence``.
///
/// The APIs exist only in the iOS 27.1 SDK. Builds against an older SDK define
/// `FENTON_IOS_SDK_BEFORE_27_1` and compile the probe out.
struct DeviceSignalsProbe: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS) && !FENTON_IOS_SDK_BEFORE_27_1
        if #available(iOS 27.1, *) {
            content.modifier(DuoSignalProbe27())
        } else {
            content
        }
        #else
        content
        #endif
    }
}

#if os(iOS) && !FENTON_IOS_SDK_BEFORE_27_1
@available(iOS 27.1, *)
private struct DuoSignalProbe27: ViewModifier {
    @Environment(\.toolbarVerticalEdge) private var edge

    func body(content: Content) -> some View {
        content
            .onChange(of: edge, initial: true) { _, newEdge in
                HingePresence.shared.record(hinge: nil, hasVerticalBar: newEdge != nil)
            }
            .onHingeChange { _, context in
                HingePresence.shared.record(hinge: context.hinge.map(HingeState.init))
            }
    }
}

@available(iOS 27.1, *)
extension HingeState {
    init(_ hinge: DeviceHinge) {
        switch hinge.status {
        case .closed: self = .closed
        case .fullyOpen: self = .fullyOpen
        default: self = .partiallyOpen
        }
    }
}
#endif

extension View {
    /// Records Duo hinge signals for orientation support.
    func observesDeviceSignals() -> some View { modifier(DeviceSignalsProbe()) }
}
