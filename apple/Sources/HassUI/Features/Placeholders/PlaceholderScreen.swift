#if os(iOS)
import HassCore
import SwiftUI

/// A tab that hasn't been ported yet.
struct PlaceholderScreen: View {
    var title: String
    var symbol: String

    var body: some View {
        ContentUnavailableView(title, systemImage: symbol, description: Text("Coming in a later update."))
            .navigationTitle(title)
    }
}

/// Settings until the real page lands: shows the server, connection status and Sign Out.
struct SettingsPlaceholder: View {
    @Environment(AppSession.self) private var session
    @Environment(HassConnection.self) private var connection

    var body: some View {
        Form {
            Section("Home Assistant") {
                LabeledContent("Server", value: connection.server.baseURL.host() ?? connection.server.baseURL.absoluteString)
                LabeledContent("Connection", value: statusText)
            }
            Section {
                Button("Sign Out", role: .destructive) { session.signOut() }
            }
        }
        .navigationTitle("Settings")
    }

    private var statusText: String {
        switch connection.status {
        case .disconnected: "Disconnected"
        case .connecting: "Connecting…"
        case let .connected(version): "Connected (\(version))"
        case .waitingToReconnect: "Reconnecting…"
        case .rejected: "Signed out by server"
        }
    }
}
#endif
