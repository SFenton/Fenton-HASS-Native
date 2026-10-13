import Foundation

/// The Media page (web route `/at-a-glance/media`): every TV and media source in the house, by room.
///
/// Source: `ha-sfenton-react-dash@9ac2a46:src/pages/DashboardViewPage.tsx` `MediaPage` (lines 2749-2867), its
/// sections `src/constants/portedDashboard.ts` `MEDIA_SECTIONS` (827-842) and the Music Room's source cards
/// `src/constants/roomPages.ts` (352-408). Copy from `src/i18n/locales/en/pages/media.json`.
public enum MediaPageConfig {
    /// One tile on the page.
    public struct Card: Hashable, Sendable, Identifiable {
        /// Title, entity, icon, action, active states and labels, drawn like a remote's device tile.
        public var device: MediaRemoteDevice
        /// The remote the tile opens (web `hash`), or `nil` when it runs ``MediaRemoteDevice/action``.
        public var remoteId: String?
        /// Takes the whole row (web `span: 'full'`).
        public var isFullWidth: Bool
        /// Icon while off, unavailable or unknown (web `stateIcons`).
        public var offIcon: String?
        /// The section the card sits in, so ids stay unique.
        public var section: String

        public var id: String { "\(section).\(device.title)" }

        /// The remote this tile opens.
        public var remote: MediaRemoteConfig? { remoteId.flatMap(MediaRemotes.config(id:)) }
    }

    /// One room on the page. The first card leads on its own row; the rest share a grid (web `lead-row`).
    public struct Section: Hashable, Sendable, Identifiable {
        public var title: String
        public var cards: [Card]
        public var id: String { title }

        /// The card on the lead row.
        public var lead: Card? { cards.first }
        /// The cards under the lead.
        public var followUps: [Card] { Array(cards.dropFirst()) }
    }

    /// States that count as on for a media player card (web `mediaPageCardFromItem` `activeStates`).
    static let playerActiveStates = ["on", "playing"]

    /// Labels a source tile: "On" while one of `active` is the room's source, "Off" otherwise
    /// (web `musicRoomSourceLabels`).
    static func sourceLabels(active: [String]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: MediaRemotes.MusicRoom.Source.all.map { ($0, active.contains($0) ? "On" : "Off") })
    }

    /// The page's sections in web order: Living Room, Music Room, Theater Room.
    public static let sections: [Section] = [livingRoom, musicRoom, theaterRoom]

    /// Every card, in page order.
    public static var cards: [Card] { sections.flatMap(\.cards) }

    // MARK: - Living Room (portedDashboard.ts:828-833)

    static let livingRoom = Section(title: "Living Room", cards: [
        Card(
            device: MediaRemoteDevice("Living Room SHIELD", entityId: "media_player.living_room_shield", icon: "mdi:television",
                                      activeStates: playerActiveStates, semantics: .state),
            remoteId: "living-room-shield", isFullWidth: true, offIcon: "mdi:television-off", section: "Living Room"
        ),
    ])

    // MARK: - Music Room (roomPages.ts:352-408)

    static let musicRoom: Section = {
        typealias M = MediaRemotes.MusicRoom
        let section = "Music Room"
        func source(_ title: String, icon: String, active: [String], action: MediaRemoteAction) -> Card {
            Card(
                device: MediaRemoteDevice(title, entityId: M.activeMediaSourceEntityId, icon: icon, action: action,
                                          activeStates: active, semantics: .selectedWhen(active),
                                          stateLabels: sourceLabels(active: active)),
                remoteId: nil, isFullWidth: false, offIcon: nil, section: section
            )
        }
        return Section(title: section, cards: [
            Card(
                device: MediaRemoteDevice("Music Room Remote", entityId: M.controlEntityId, icon: "mdi:remote", semantics: .state),
                remoteId: "music-room-remote", isFullWidth: true, offIcon: nil, section: section
            ),
            source("Xbox", icon: "mdi:microsoft-xbox", active: [M.Source.xbox, M.Source.fortnite], action: M.xboxSourceToggle),
            source("Server", icon: "mdi:server", active: [M.Source.server], action: M.serverToggle),
            source("Windows PC", icon: "mdi:microsoft-windows", active: [M.Source.windowsPC], action: M.windowsPCToggle),
            // Quick App Launch (web `app-launch` layout, hidden on the room page and shown here).
            source("Fortnite", icon: "mdi:gamepad-variant", active: [M.Source.fortnite], action: M.fortnite),
        ])
    }()

    // MARK: - Theater Room (portedDashboard.ts:834-841)

    static let theaterRoom: Section = {
        let section = "Theater Room"
        func scripted(_ title: String, entityId: String, icon: String, script: String) -> Card {
            Card(
                device: MediaRemoteDevice(title, entityId: entityId, icon: icon, action: .service("script", script),
                                          activeStates: playerActiveStates, semantics: .toggleOnWhen(playerActiveStates)),
                remoteId: nil, isFullWidth: false, offIcon: nil, section: section
            )
        }
        return Section(title: section, cards: [
            Card(
                device: MediaRemoteDevice("Theater Room", entityId: "media_player.sony_projector", icon: "mdi:projector",
                                          activeStates: playerActiveStates, semantics: .state),
                remoteId: "theater-room-shield", isFullWidth: true, offIcon: nil, section: section
            ),
            scripted("Nintendo Switch", entityId: "input_boolean.is_nintendo_switch_active", icon: "mdi:nintendo-switch",
                     script: "theater_room_nintendo_switch"),
            scripted("Theater SHIELD", entityId: "input_boolean.is_theater_shield_active", icon: "mdi:television",
                     script: "theater_room_tv_movie"),
        ])
    }()
}
