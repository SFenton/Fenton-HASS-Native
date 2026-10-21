#if DEBUG
import HassDesign
import SwiftUI

/// Gallery page for the shell's two trailing header buttons (``ShellHeaderItems``): Quick Links and Profile in the real
/// navigation bar, on fixtures, with no sign-in. It shows every state of the Profile button
/// (`.agents/design/direction-g.md`, Navigation) so journeys and screenshots reach the ones a signed-in house never shows (no
/// name yet, nine or more waiting). Launch with `FENTON_GALLERY=shell-header`.
///
/// Switches:
/// - `FENTON_GALLERY_PROFILE`: the display name (default `Stephen Fenton`), or `none` for no name yet.
/// - `FENTON_GALLERY_BADGE`: the attention count (default 0).
/// - `FENTON_GALLERY_OFFLINE`: `1` shows the offline badge on Profile (the path state cannot be toggled in a simulator).
/// - `FENTON_GALLERY_SCHEME`: `light` draws the page in the light scheme (default dark, like the shell).
/// - `FENTON_GALLERY_PUSHED=1`: starts on a pushed page, with Back leading.
/// - `FENTON_GALLERY_PLAIN=1`: a solid black page instead of the house backdrop, so a screenshot's glass edges and disc can
///   be measured in pixels.
struct ShellHeaderGallery: View {
    private static let environment = ProcessInfo.processInfo.environment
    private var environment: [String: String] { Self.environment }

    /// The display name the Profile button shows, nil when `FENTON_GALLERY_PROFILE=none`.
    var profileName: String? {
        let value = environment["FENTON_GALLERY_PROFILE"] ?? "Stephen Fenton"
        return value == "none" ? nil : value
    }

    /// The attention count the badge shows.
    var isOffline: Bool { environment["FENTON_GALLERY_OFFLINE"] == "1" }
    var attentionCount: Int { environment["FENTON_GALLERY_BADGE"].flatMap(Int.init) ?? 0 }

    @State private var lastAction = "none"
    @State private var path: [Page] = Self.environment["FENTON_GALLERY_PUSHED"] == "1" ? [.pushed] : []

    private enum Page: Hashable { case pushed }

    var body: some View {
        NavigationStack(path: $path) {
            page(title: "Home", showsPush: true)
                .navigationDestination(for: Page.self) { _ in page(title: "Master Bedroom", showsPush: false) }
        }
        .preferredColorScheme(environment["FENTON_GALLERY_SCHEME"] == "light" ? .light : .dark)
    }

    private func page(title: String, showsPush: Bool) -> some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.m) {
            if showsPush {
                NavigationLink("Push a page", value: Page.pushed)
                    .accessibilityIdentifier("shellHeader.push")
            }
            Spacer()
            GalleryLastCall(text: lastAction, title: "Last action")
        }
        .padding(HassTokens.Spacing.l)
        .modifier(GalleryPageChrome(plain: environment["FENTON_GALLERY_PLAIN"] == "1"))
        .navigationTitle(title)
        .toolbar {
            ShellHeaderItems(
                profileName: profileName,
                attentionCount: attentionCount,
                isOffline: isOffline,
                openQuickLinks: { lastAction = "quick-links" },
                openAccount: { lastAction = "profile" }
            )
        }
    }
}

/// The shell's own page chrome (backdrop, header fade, title in the header row), so the buttons sit where they do on a real
/// page; or a plain black page for measuring.
private struct GalleryPageChrome: ViewModifier {
    var plain: Bool

    func body(content: Content) -> some View {
        if plain {
            #if os(iOS)
            content
                .background(Color.black.ignoresSafeArea())
                .toolbarTitleDisplayMode(.inlineLarge)
            #else
            content.background(Color.black.ignoresSafeArea())
            #endif
        } else {
            content.pageChrome()
        }
    }
}
#endif
