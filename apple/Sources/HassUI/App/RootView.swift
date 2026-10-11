import HassCore
import SwiftUI

/// The app's root: sign-in or the main tabs, plus scene-phase handling.
public struct RootView: View {
    @State private var session = AppSession()
    @Environment(\.scenePhase) private var scenePhase

    public init() {}

    public var body: some View {
        Group {
            switch session.phase {
            case .signedOut:
                LoginView { server, tokens in try session.didSignIn(server: server, tokens: tokens) }
            case let .signedIn(connection, _):
                MainTabView()
                    .environment(connection)
                    .environment(connection.store)
                    .environment(session)
                    .readsWindowHinge()
                    .onChange(of: connection.status) { _, status in
                        if status == .rejected { session.signOut() }
                    }
            }
        }
        .observesDeviceSignals()
        .onChange(of: scenePhase) { _, phase in
            guard case let .signedIn(_, lifecycle) = session.phase else { return }
            switch phase {
            case .active: lifecycle.didBecomeActive()
            case .background: lifecycle.didEnterBackground()
            default: break
            }
        }
    }
}
