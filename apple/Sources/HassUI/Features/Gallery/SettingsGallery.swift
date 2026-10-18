#if DEBUG
import HassCore
import HassDesign
import SwiftUI

/// Gallery page for the Settings tab's root list (`FENTON_GALLERY=settings`): ``SettingsScreen`` in a stack with the
/// shell's page chrome (house backdrop, header fade), on an empty store, so the scroll cost probe and journeys reach the
/// tab without signing in. Rows that open a sheet or push do nothing here without the shell.
struct SettingsGallery: View {
    @State private var store = EntityStore()

    var body: some View {
        NavigationStack {
            SettingsTabRoot()
                .pageChrome()
        }
        .environment(store)
        .preferredColorScheme(.dark)
    }
}
#endif
