import SwiftUI

/// Watch app stub. Scope: `.agents/design/apple/watchos.md`.
@main
struct FentonHomeWatchApp: App {
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 8) {
                Image(systemName: "house.fill").font(.title)
                Text("Fenton Home").font(.headline)
                Text("Coming soon").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}
