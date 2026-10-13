import HassCore
import HassDesign
import SwiftUI

/// The Media page (web `MediaPage`, `DashboardViewPage.tsx:2794`; spec `.agents/pages/media/spec.md`).
///
/// One section per room: the room's TV leads on its own row and opens its remote (``MediaRemoteSheet``); the
/// room's sources and quick launches share a grid under it and run their command in place. Sections sit side
/// by side when the page is wide enough (web `ResponsiveSectionGrid`); that is a grid, not a split.
public struct MediaScreen: View {
    private let store: EntityStore
    private let caller: any HassServiceCalling
    private let imageServer: HassServer?
    /// The Music Room's controller, shared by its source tiles and its remote so optimistic source changes show
    /// in both (web `OptimisticActionStateBoundary` around the page).
    @State private var musicRoom: MediaRemoteController
    @State private var remote: MediaRemoteConfig?
    private let initialTab: MediaRemoteTab
    @ScaledMetric(relativeTo: .body) private var minSectionWidth: CGFloat = 340

    /// Creates the page.
    /// - Parameters:
    ///   - store: Live entity state.
    ///   - caller: Where service calls go (the connection, or a recorder in the gallery and tests).
    ///   - imageServer: Serves remote app artwork; `nil` shows icon fallbacks.
    ///   - openRemote: A remote to open at once (gallery and journeys).
    ///   - initialTab: The first tab of a remote opened from the page.
    public init(store: EntityStore, caller: any HassServiceCalling, imageServer: HassServer? = nil,
                openRemote: MediaRemoteConfig? = nil, initialTab: MediaRemoteTab = .controls) {
        self.store = store
        self.caller = caller
        self.imageServer = imageServer
        self.initialTab = initialTab
        _musicRoom = State(initialValue: MediaRemoteController(config: MediaRemotes.musicRoom, store: store, caller: caller))
        _remote = State(initialValue: openRemote)
    }

    public var body: some View {
        ScrollView {
            DynamicGridLayout(minCellWidth: minSectionWidth, maxColumns: 3, spacing: HassTokens.Spacing.xl) {
                ForEach(MediaPageConfig.sections) { section in
                    MediaSectionView(section: section, controller: musicRoom) { remote = $0 }
                }
            }
            .padding(.horizontal, HassTokens.Spacing.l)
            .padding(.vertical, HassTokens.Spacing.m)
        }
        .scrollTelemetry("Media")
        .accessibilityIdentifier("media.scroll")
        .navigationTitle("Media")
        .sheet(item: $remote) { config in
            Group {
                if config.id == MediaRemotes.musicRoom.id {
                    MediaRemoteSheet(controller: musicRoom, imageServer: imageServer, initialTab: initialTab)
                } else {
                    MediaRemoteSheet(config: config, store: store, caller: caller, imageServer: imageServer, initialTab: initialTab)
                }
            }
            .galleryLastCallBanner()
            .mediaRemotePresentation()
        }
    }
}

/// One room: a header, the lead tile on its own row, then the room's other tiles.
struct MediaSectionView: View {
    var section: MediaPageConfig.Section
    var controller: MediaRemoteController
    var openRemote: (MediaRemoteConfig) -> Void
    @ScaledMetric(relativeTo: .subheadline) private var minTileWidth: CGFloat = 140

    var body: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.m) {
            Text(section.title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(HassTokens.Ink.primary)
                .accessibilityAddTraits(.isHeader)
            if let lead = section.lead {
                MediaCardTile(card: lead, controller: controller, openRemote: openRemote)
            }
            if !section.followUps.isEmpty {
                DynamicGridLayout(minCellWidth: minTileWidth, maxColumns: 4) {
                    ForEach(section.followUps) { card in
                        MediaCardTile(card: card, controller: controller, openRemote: openRemote)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("media.section.\(MediaCardTile.slug(section.title))")
    }
}

/// One media tile: opens a remote, or runs its command.
struct MediaCardTile: View {
    var card: MediaPageConfig.Card
    var controller: MediaRemoteController
    var openRemote: (MediaRemoteConfig) -> Void

    var body: some View {
        let display = controller.display(card.device)
        let look = Self.look(card, display: display)
        Group {
            if let remote = card.remote {
                // A remote opens whatever the TV's state: its power button is how the TV turns on.
                GlassTile(title: card.device.title, subtitle: display.subtitle, symbol: look.symbol,
                          tint: RemoteStyle.media, isActive: display.isActive, kind: .navigate) { openRemote(remote) }
            } else {
                GlassTile(title: card.device.title, subtitle: display.subtitle, symbol: look.symbol,
                          tint: RemoteStyle.media, isActive: display.isActive, isUnavailable: display.isDisabled,
                          kind: look.kind) { controller.tap(card.device) }
            }
        }
        .accessibilityIdentifier("media.card.\(Self.slug(card.section)).\(Self.slug(card.device.title))")
    }

    /// The tile's icon and tap semantics for its current display.
    static func look(_ card: MediaPageConfig.Card, display: MediaRemoteController.DeviceDisplay) -> (symbol: String, kind: GlassTile.Kind) {
        let off = MediaRemoteState.isOff(display.state)
        let icon = off ? card.offIcon ?? card.device.icon : card.device.icon
        let kind: GlassTile.Kind = switch display.semantics {
        case .toggle, .selection: .toggle
        case .command, .state: .command
        }
        return (SymbolMap.symbol(for: icon), kind)
    }

    /// `Living Room SHIELD` → `living-room-shield`.
    static func slug(_ text: String) -> String {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.joined(separator: "-")
    }
}
