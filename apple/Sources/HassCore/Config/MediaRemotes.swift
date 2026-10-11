import Foundation

/// The house's media remotes, ported from the React dashboard.
///
/// Source: `ha-sfenton-react-dash@9ac2a46:src/constants/mediaRemotes.ts` (service calls, entity IDs, optimistic
/// intents and revert times are verbatim) and `src/i18n/locales/en/pages/media.json` (Music Room copy).
public enum MediaRemotes {
    /// Every remote, in the web's `MEDIA_REMOTE_CONFIGS` order.
    public static let all: [MediaRemoteConfig] = [livingRoomShield, masterBedroomAppleTV, theaterRoomShield, musicRoom]

    /// Looks up a remote by its id (the web hash without `#`).
    public static func config(id: String) -> MediaRemoteConfig? {
        let id = id.hasPrefix("#") ? String(id.dropFirst()) : id
        return all.first { $0.id == id }
    }

    /// The remote a media player opens (web `MEDIA_PAGE_REMOTE_HASH_BY_ENTITY_ID`, surfaceSemantics.ts:83).
    public static func config(forMediaPlayer entityId: String) -> MediaRemoteConfig? {
        let ids = [
            "media_player.living_room_shield": "living-room-shield",
            "media_player.living_room_shield_2": "living-room-shield",
            "media_player.music_room_tv_android": "music-room-remote",
            "media_player.sony_projector": "theater-room-shield",
            "media_player.theater_room_shield": "theater-room-shield",
        ]
        return ids[entityId].flatMap { config(id: $0) }
    }

    // MARK: - Builders (mediaRemotes.ts:107-148)

    static let deviceOffStates = ["off", "unavailable", "unknown"]

    static func remoteCommand(_ remote: String, _ command: String) -> MediaRemoteAction {
        .service("remote", "send_command", target: remote, data: ["command": .string(command)])
    }

    static func appleTVCommand(_ command: String) -> MediaRemoteAction {
        .service("script", "apple_tv_remote_send_command", data: [
            "remote_entity": .string("remote.master_bedroom_apple_tv"), "command": .string(command),
        ])
    }

    static func androidAppLauncher(entity: String, remote: String, appId: String, extra: [String: JSONValue] = [:]) -> MediaRemoteAction {
        var data: [String: JSONValue] = ["entity": .string(entity), "remote_entity": .string(remote), "app_id": .string(appId)]
        data.merge(extra) { _, new in new }
        return .service("script", "launch_app_on_media_player", data: data)
    }

    static func appleTVAppLauncher(_ appName: String) -> MediaRemoteAction {
        .service("script", "launch_app_on_apple_tv", data: [
            "entity": .string("media_player.master_bedroom_apple_tv"),
            "app_name": .string(appName),
            "remote_entity": .string("remote.master_bedroom_apple_tv"),
        ])
    }

    static func powerColor(_ entityIds: [String], _ inactiveStates: [String]) -> IconColorRule {
        IconColorRule(entityIds: entityIds, inactiveStates: inactiveStates)
    }

    static func inputButtonPress(_ target: String) -> MediaRemoteCommand {
        .service(ServiceCall("input_button", "press", target: target))
    }

    /// `pcPowerAction` (mediaRemotes.ts:122): pressing the "off" button while on, else the "on" button.
    static func pcPowerAction(on onTarget: String, off offTarget: String) -> MediaRemoteAction {
        .state(entityId: nil, cases: [.init(["on"], inputButtonPress(offTarget))], otherwise: inputButtonPress(onTarget))
    }

    struct AndroidApp {
        var title: String
        var appId: String
        var imagePath: String
        var whiteBackground = false
    }

    /// `androidApps` (mediaRemotes.ts:368).
    static let androidApps: [AndroidApp] = [
        .init(title: "Plex", appId: "com.plexapp.android", imagePath: "/local/images/apps/plex.png"),
        .init(title: "YouTube", appId: "com.google.android.youtube.tv", imagePath: "/local/images/apps/youtube.png", whiteBackground: true),
        .init(title: "Netflix", appId: "com.netflix.ninja", imagePath: "/local/images/apps/netflix.png"),
        .init(title: "Prime Video", appId: "com.amazon.amazonvideo.livingroom", imagePath: "/local/images/apps/prime.jpeg"),
        .init(title: "Paramount+", appId: "com.cbs.ott", imagePath: "/local/images/apps/paramount.png"),
        .init(title: "Disney+", appId: "com.disney.disneyplus", imagePath: "/local/images/apps/disney.png"),
    ]

    static func androidAppCards(entity: String, remote: String, extra: [String: JSONValue] = [:]) -> [MediaRemoteApp] {
        androidApps.map {
            MediaRemoteApp(
                $0.title, action: androidAppLauncher(entity: entity, remote: remote, appId: $0.appId, extra: extra),
                imagePath: $0.imagePath, whiteBackground: $0.whiteBackground
            )
        }
    }

    /// The d-pad, back, home and playback buttons every SHIELD-style remote shares.
    static func androidButtons(remote: String) -> (
        up: MediaRemoteButton, left: MediaRemoteButton, select: MediaRemoteButton, right: MediaRemoteButton,
        down: MediaRemoteButton, back: MediaRemoteButton, home: MediaRemoteButton, pause: MediaRemoteButton, play: MediaRemoteButton
    ) {
        (
            MediaRemoteButton("Up", icon: "mdi:chevron-up", action: remoteCommand(remote, "DPAD_UP")),
            MediaRemoteButton("Left", icon: "mdi:chevron-left", action: remoteCommand(remote, "DPAD_LEFT")),
            MediaRemoteButton("Select", icon: " ", action: remoteCommand(remote, "DPAD_CENTER")),
            MediaRemoteButton("Right", icon: "mdi:chevron-right", action: remoteCommand(remote, "DPAD_RIGHT")),
            MediaRemoteButton("Down", icon: "mdi:chevron-down", action: remoteCommand(remote, "DPAD_DOWN")),
            MediaRemoteButton("Back", icon: "mdi:triangle-down", rotation: 90, action: remoteCommand(remote, "BACK")),
            MediaRemoteButton("Home", icon: "mdi:circle", action: remoteCommand(remote, "HOME")),
            MediaRemoteButton("Pause", icon: "mdi:pause", action: remoteCommand(remote, "MEDIA_PAUSE")),
            MediaRemoteButton("Play", icon: "mdi:play", action: remoteCommand(remote, "MEDIA_PLAY"))
        )
    }

    static func sonosVolumeButtons(_ speaker: String) -> (down: MediaRemoteButton, mute: MediaRemoteButton, up: MediaRemoteButton) {
        (
            MediaRemoteButton("Volume Down", icon: "mdi:volume-minus", action: .service("media_player", "volume_down", target: speaker)),
            MediaRemoteButton("Mute", icon: "mdi:volume-mute", action: .service("script", "toggle_sonos_mute", data: ["sonosdevice": .array([.string(speaker)])])),
            MediaRemoteButton("Volume Up", icon: "mdi:volume-plus", action: .service("media_player", "volume_up", target: speaker))
        )
    }

    // MARK: - Living Room SHIELD (mediaRemotes.ts:387)

    public static let livingRoomShield: MediaRemoteConfig = {
        let remote = "remote.living_room_shield"
        let shield = "media_player.living_room_shield_2"
        let buttons = androidButtons(remote: remote)
        let volume = sonosVolumeButtons("media_player.sonos")
        return MediaRemoteConfig(
            id: "living-room-shield", title: "Living Room SHIELD", roomTitle: "Living Room", remoteTitle: "Living Room SHIELD Remote",
            mediaEntityId: shield, controlEntityId: shield,
            power: MediaRemoteButton("Power", icon: "mdi:power", action: remoteCommand(remote, "POWER"), iconColorRule: powerColor([shield], deviceOffStates)),
            up: buttons.up, left: buttons.left, select: buttons.select, right: buttons.right, down: buttons.down,
            back: buttons.back, home: buttons.home,
            keyboard: MediaRemoteButton("Keyboard", icon: "mdi:keyboard", action: .command(.textPrompt(targetEntityId: shield))),
            pause: buttons.pause, play: buttons.play,
            volumeTitle: "Sonos Volume", volumeEntityId: "media_player.sonos",
            volumeDown: volume.down, volumeMute: volume.mute, volumeUp: volume.up,
            apps: androidAppCards(entity: "media_player.living_room_shield", remote: remote)
        )
    }()

    // MARK: - Master Bedroom Apple TV (mediaRemotes.ts:413)

    public static let masterBedroomAppleTV: MediaRemoteConfig = {
        let appleTV = "media_player.master_bedroom_apple_tv"
        let volume = sonosVolumeButtons("media_player.primary_bedroom")
        return MediaRemoteConfig(
            id: "master-bedroom-apple-tv", title: "Apple TV", roomTitle: "Master Bedroom", remoteTitle: "Apple TV Remote",
            mediaEntityId: appleTV, controlEntityId: appleTV,
            power: MediaRemoteButton("Power", icon: "mdi:power", action: .service("script", "apple_tv_power_on_off"),
                                     iconColorRule: powerColor([appleTV], ["off", "standby", "unavailable"])),
            up: MediaRemoteButton("Up", icon: "mdi:chevron-up", action: appleTVCommand("up")),
            left: MediaRemoteButton("Left", icon: "mdi:chevron-left", action: appleTVCommand("left")),
            select: MediaRemoteButton("Select", icon: "mdi:circle", action: appleTVCommand("select")),
            right: MediaRemoteButton("Right", icon: "mdi:chevron-right", action: appleTVCommand("right")),
            down: MediaRemoteButton("Down", icon: "mdi:chevron-down", action: appleTVCommand("down")),
            back: MediaRemoteButton("Menu", icon: "mdi:chevron-left", action: appleTVCommand("menu")),
            home: MediaRemoteButton("Home", icon: "mdi:home", action: appleTVCommand("home")),
            pause: MediaRemoteButton("Pause", icon: "mdi:pause", action: appleTVCommand("pause")),
            play: MediaRemoteButton("Play", icon: "mdi:play", action: appleTVCommand("play")),
            volumeTitle: "Volume", volumeEntityId: "media_player.primary_bedroom",
            volumeDown: volume.down, volumeMute: volume.mute, volumeUp: volume.up,
            apps: [MediaRemoteApp("Plex", action: appleTVAppLauncher("Plex"), imagePath: "/local/images/apps/plex.png")]
        )
    }()

    // MARK: - Theater Room SHIELD (mediaRemotes.ts:438)

    public static let theaterRoomShield: MediaRemoteConfig = {
        let remote = "remote.theater_shield_remote"
        let shield = "media_player.theater_room_shield"
        let projector = "media_player.sony_projector"
        let receiver = "media_player.theater"
        let buttons = androidButtons(remote: remote)
        return MediaRemoteConfig(
            id: "theater-room-shield", title: "Theater Room SHIELD", roomTitle: "Theater Room", remoteTitle: "Theater Room SHIELD Remote",
            mediaEntityId: shield, controlEntityId: shield,
            power: MediaRemoteButton("Power", icon: "mdi:power", action: .service("script", "toggle_on_off_theater_room"),
                                     iconColorRule: powerColor([shield], deviceOffStates)),
            up: buttons.up, left: buttons.left, select: buttons.select, right: buttons.right, down: buttons.down,
            back: buttons.back, home: buttons.home,
            keyboard: MediaRemoteButton("Keyboard", icon: "mdi:keyboard", action: .command(.textPrompt(targetEntityId: shield))),
            pause: buttons.pause, play: buttons.play,
            volumeTitle: "Yamaha Volume", volumeEntityId: receiver,
            volumeDown: MediaRemoteButton("Volume Down", icon: "mdi:volume-minus", action: .service("media_player", "volume_down", target: receiver)),
            volumeMute: MediaRemoteButton("Mute", icon: "mdi:volume-mute", action: .service("media_player", "volume_mute", target: receiver, data: ["is_volume_muted": .bool(true)])),
            volumeUp: MediaRemoteButton("Volume Up", icon: "mdi:volume-plus", action: .service("media_player", "volume_up", target: receiver)),
            showVolumeWhenOff: true,
            apps: androidAppCards(entity: shield, remote: remote, extra: ["turn_on_projector": .bool(true)]),
            devices: [
                MediaRemoteDevice("Projector", entityId: projector, icon: "mdi:projector", action: .service("media_player", "toggle", target: projector)),
                MediaRemoteDevice("Yamaha AVR", entityId: receiver, icon: "mdi:audio-video", action: .service("media_player", "toggle", target: receiver)),
                MediaRemoteDevice("Theater Room SHIELD", entityId: shield, icon: "mdi:remote-tv", action: .service("media_player", "toggle", target: shield)),
                MediaRemoteDevice("Theater Room PC", entityId: "input_boolean.theater_pc_power", icon: "mdi:projector",
                                  action: pcPowerAction(on: "input_button.theater_pc_on", off: "input_button.theater_pc_off")),
            ]
        )
    }()

    // MARK: - Music Room (mediaRemotes.ts:158-583)

    /// Music Room entity IDs, states, revert times and actions.
    public enum MusicRoom {
        public static let controlEntityId = "media_player.music_room_tv_android"
        public static let xboxEntityId = "media_player.xbox"
        public static let remoteEntityId = "remote.music_room_tv_android"
        public static let volumeEntityId = "media_player.beam"
        public static let mediaSourceEntityId = "input_select.music_room_media_source"
        public static let activeMediaSourceEntityId = "sensor.music_room_active_media_source"
        public static let xboxHdmiStatusEntityId = "sensor.music_room_music_room_sync_box_hdmi1_status"
        public static let hueSyncPowerEntityId = "switch.music_room_music_room_sync_box_power"
        public static let hueSyncLightSyncEntityId = "switch.music_room_music_room_sync_box_light_sync"
        public static let hueSyncBrightnessEntityId = "number.music_room_music_room_sync_box_brightness"
        public static let hueSyncHdmiInputEntityId = "select.music_room_music_room_sync_box_hdmi_input"
        public static let hueSyncModeEntityId = "select.music_room_music_room_sync_box_sync_mode"
        public static let hueSyncIntensityEntityId = "select.music_room_music_room_sync_box_intensity"
        public static let hueSyncHdmiStatusEntityIds = [
            xboxHdmiStatusEntityId,
            "sensor.music_room_music_room_sync_box_hdmi2_status",
            "sensor.music_room_music_room_sync_box_hdmi3_status",
            "sensor.music_room_music_room_sync_box_hdmi4_status",
        ]

        /// `MUSIC_ROOM_MEDIA_SOURCE_STATES`.
        public enum Source {
            public static let fortnite = "Fortnite"
            public static let off = "Off"
            public static let server = "Server"
            public static let tv = "TV"
            public static let windowsPC = "Windows PC"
            public static let xbox = "Xbox"
            static let all = [fortnite, off, server, tv, windowsPC, xbox]
        }

        /// `MUSIC_ROOM_COMMAND_REVERT_MS`, `MUSIC_ROOM_XBOX_*` and `HUE_SYNC_OPTIMISTIC_REVERT_MS`.
        public enum Revert {
            public static let fortnite: Duration = .seconds(120)
            public static let server: Duration = .seconds(20)
            public static let tv: Duration = .seconds(20)
            public static let windowsPC: Duration = .seconds(20)
            public static let xbox: Duration = .seconds(90)
            public static let xboxOff: Duration = .seconds(180)
            public static let hueSync: Duration = .seconds(8)
        }

        public static let xboxActiveHold: Duration = .seconds(45)
        public static let xboxActiveStates = ["on", "playing", "paused"]
        static let xboxLinkedState = "linked"

        static let mediaOptimisticEntityIds = [
            activeMediaSourceEntityId, controlEntityId, xboxEntityId, xboxHdmiStatusEntityId,
            hueSyncPowerEntityId, hueSyncLightSyncEntityId, hueSyncHdmiInputEntityId,
        ]
        static let hueSyncOptimisticEntityIds = [
            hueSyncPowerEntityId, hueSyncLightSyncEntityId, hueSyncBrightnessEntityId,
            hueSyncHdmiInputEntityId, hueSyncModeEntityId, hueSyncIntensityEntityId,
        ]

        /// `musicRoomXboxState` (mediaRemotes.ts:224): on when the Xbox cloud state is active, or when the TV is on,
        /// the Sync Box is powered on HDMI 1 and HDMI 1 reports `linked`; off when anything reports a real state.
        public static func xboxState(_ states: [String: String]) -> String {
            let cloud = states[xboxEntityId]
            let hdmi = states[xboxHdmiStatusEntityId]
            let tv = states[controlEntityId]
            let power = states[hueSyncPowerEntityId]
            let input = states[hueSyncHdmiInputEntityId]
            let cloudActive = cloud.map(xboxActiveStates.contains) ?? false
            let linkedOnActivePath = tv.map { $0 != "off" && !MediaRemoteState.isUnavailable($0) } == true
                && power == "on"
                && input?.hasSuffix(" 1") == true
                && hdmi == xboxLinkedState
            if cloudActive || linkedOnActivePath { return "on" }
            let known = [cloud, hdmi, tv, power, input].contains { $0.map { !MediaRemoteState.isUnavailable($0) } ?? false }
            return known ? "off" : "unavailable"
        }

        static func intent(_ entityId: String, _ value: String, _ revert: Duration) -> OptimisticIntent {
            OptimisticIntent(entityId, value, revertAfter: revert)
        }

        static func script(_ name: String, _ intents: [OptimisticIntent]) -> MediaRemoteCommand {
            .service(ServiceCall("script", name), optimistic: intents)
        }

        static let tvOn = script("music_room_tv", [
            intent(controlEntityId, "on", Revert.tv),
            intent(activeMediaSourceEntityId, Source.tv, Revert.tv),
            intent(hueSyncPowerEntityId, "on", Revert.tv),
            intent(hueSyncLightSyncEntityId, "off", Revert.tv),
        ])
        static let tvOff = script("music_room_tv_off", [
            intent(controlEntityId, "off", Revert.xboxOff),
            intent(activeMediaSourceEntityId, Source.off, Revert.xboxOff),
            intent(xboxEntityId, "off", Revert.xboxOff),
            intent(hueSyncPowerEntityId, "off", Revert.xboxOff),
            intent(hueSyncLightSyncEntityId, "off", Revert.xboxOff),
        ])
        static let xboxOn = script("music_room_xbox", [
            intent(xboxEntityId, "on", Revert.xbox),
            intent(controlEntityId, "on", Revert.xbox),
            intent(activeMediaSourceEntityId, Source.xbox, Revert.xbox),
            intent(hueSyncPowerEntityId, "on", Revert.xbox),
            intent(hueSyncLightSyncEntityId, "off", Revert.xbox),
            intent(hueSyncHdmiInputEntityId, "HDMI 1", Revert.xbox),
        ])
        static let xboxOff = script("music_room_xbox_off", [
            intent(xboxEntityId, "off", Revert.xboxOff),
            intent(xboxHdmiStatusEntityId, "plugged", Revert.xboxOff),
        ])
        static let serverOn = script("music_room_server", [
            intent(controlEntityId, "on", Revert.server),
            intent(activeMediaSourceEntityId, Source.server, Revert.server),
            intent(hueSyncPowerEntityId, "on", Revert.server),
            intent(hueSyncLightSyncEntityId, "off", Revert.server),
            intent(hueSyncHdmiInputEntityId, "HDMI 2", Revert.server),
        ])
        static let windowsPCOn = script("music_room_windows_pc", [
            intent(controlEntityId, "on", Revert.windowsPC),
            intent(activeMediaSourceEntityId, Source.windowsPC, Revert.windowsPC),
            intent(hueSyncPowerEntityId, "on", Revert.windowsPC),
            intent(hueSyncLightSyncEntityId, "off", Revert.windowsPC),
            intent(hueSyncHdmiInputEntityId, "HDMI 3", Revert.windowsPC),
        ])

        /// `MUSIC_ROOM_MEDIA_ACTIONS.fortnite`.
        public static let fortnite: MediaRemoteAction = .command(script("music_room_fortnite", [
            intent(xboxEntityId, "on", Revert.fortnite),
            intent(controlEntityId, "on", Revert.fortnite),
            intent(activeMediaSourceEntityId, Source.fortnite, Revert.fortnite),
            intent(hueSyncPowerEntityId, "on", Revert.fortnite),
            intent(hueSyncLightSyncEntityId, "on", Revert.fortnite),
            intent(hueSyncHdmiInputEntityId, "HDMI 1", Revert.fortnite),
        ]))
        /// `MUSIC_ROOM_MEDIA_ACTIONS.serverToggle`.
        public static let serverToggle: MediaRemoteAction = .state(
            entityId: activeMediaSourceEntityId, cases: [.init([Source.server], tvOff)], otherwise: serverOn)
        /// `MUSIC_ROOM_MEDIA_ACTIONS.tvToggle`; also the power button.
        public static let tvToggle: MediaRemoteAction = .state(
            entityId: controlEntityId, cases: [.init(["off", "unavailable", "unknown"], tvOn)], otherwise: tvOff)
        /// `MUSIC_ROOM_MEDIA_ACTIONS.windowsPcToggle`.
        public static let windowsPCToggle: MediaRemoteAction = .state(
            entityId: activeMediaSourceEntityId, cases: [.init([Source.windowsPC], tvOff)], otherwise: windowsPCOn)
        /// `MUSIC_ROOM_MEDIA_ACTIONS.xboxSourceToggle`.
        public static let xboxSourceToggle: MediaRemoteAction = .state(
            entityId: activeMediaSourceEntityId, cases: [.init([Source.xbox, Source.fortnite], tvOff)], otherwise: xboxOn)
        /// `MUSIC_ROOM_MEDIA_ACTIONS.xboxToggle`.
        public static let xboxToggle: MediaRemoteAction = .state(
            entityId: xboxEntityId, cases: [.init(xboxActiveStates + [xboxLinkedState], xboxOff)], otherwise: xboxOn)

        /// `musicRoomSourceLabels`: "On" for the active source, "Off" for every other source.
        static func sourceLabels(active: String) -> [String: String] {
            Dictionary(uniqueKeysWithValues: Source.all.map { ($0, $0 == active ? "On" : "Off") })
        }
    }

    public static let musicRoom: MediaRemoteConfig = {
        typealias M = MusicRoom
        let remote = M.remoteEntityId
        let buttons = androidButtons(remote: remote)
        let volume = sonosVolumeButtons(M.volumeEntityId)
        return MediaRemoteConfig(
            id: "music-room-remote", title: "Music Room Remote", roomTitle: "Music Room", remoteTitle: "Music Room Remote",
            mediaEntityId: M.controlEntityId, controlEntityId: M.controlEntityId,
            power: MediaRemoteButton("Power", icon: "mdi:power", action: M.tvToggle,
                                     iconColorRule: powerColor([M.controlEntityId], deviceOffStates),
                                     semantics: .toggleOnUnless(deviceOffStates)),
            up: buttons.up, left: buttons.left, select: buttons.select, right: buttons.right, down: buttons.down,
            back: buttons.back, home: buttons.home, pause: buttons.pause, play: buttons.play,
            volumeTitle: "Sonos Beam Volume", volumeEntityId: M.volumeEntityId,
            volumeDown: volume.down, volumeMute: volume.mute, volumeUp: volume.up,
            showVolumeWhenOff: true,
            appSectionTitle: "Quick App Launch",
            // The web bundles Fortnite artwork with the dashboard (src/assets/apps/fortnite.jpg); the app shows the
            // icon fallback until that artwork is published under /local/images/apps.
            apps: [MediaRemoteApp("Fortnite", action: M.fortnite, icon: "mdi:gamepad-variant",
                                  stateEntityId: M.activeMediaSourceEntityId, activeStates: [M.Source.fortnite],
                                  semantics: .selectedWhen([M.Source.fortnite]))],
            devices: [
                MediaRemoteDevice("TV", entityId: M.controlEntityId, icon: "mdi:television", action: M.tvToggle,
                                  semantics: .toggleOnUnless(deviceOffStates)),
                MediaRemoteDevice("Xbox", entityId: M.xboxEntityId, icon: "mdi:microsoft-xbox", action: M.xboxToggle,
                                  activeHold: M.xboxActiveHold,
                                  activeHoldResetEntityIds: [M.controlEntityId, M.hueSyncPowerEntityId, M.hueSyncHdmiInputEntityId, M.activeMediaSourceEntityId],
                                  activeStates: ["on"], semantics: .toggleOnWhen(M.xboxActiveStates),
                                  stateEntityIds: [M.xboxEntityId, M.xboxHdmiStatusEntityId, M.controlEntityId, M.hueSyncPowerEntityId, M.hueSyncHdmiInputEntityId],
                                  stateResolver: .musicRoomXbox),
                MediaRemoteDevice("Server", entityId: M.activeMediaSourceEntityId, icon: "mdi:server", action: M.serverToggle,
                                  activeStates: [M.Source.server], semantics: .selectedWhen([M.Source.server]),
                                  stateLabels: M.sourceLabels(active: M.Source.server)),
                MediaRemoteDevice("Windows PC", entityId: M.activeMediaSourceEntityId, icon: "mdi:microsoft-windows", action: M.windowsPCToggle,
                                  activeStates: [M.Source.windowsPC], semantics: .selectedWhen([M.Source.windowsPC]),
                                  stateLabels: M.sourceLabels(active: M.Source.windowsPC)),
                MediaRemoteDevice("Sonos Beam", entityId: M.volumeEntityId, icon: "mdi:speaker", semantics: .state),
            ],
            hueSync: HueSyncConfig(
                powerEntityId: M.hueSyncPowerEntityId, lightSyncEntityId: M.hueSyncLightSyncEntityId,
                syncModeEntityId: M.hueSyncModeEntityId, intensityEntityId: M.hueSyncIntensityEntityId,
                brightnessEntityId: M.hueSyncBrightnessEntityId, hdmiInputEntityId: M.hueSyncHdmiInputEntityId,
                hdmiStatusEntityIds: M.hueSyncHdmiStatusEntityIds
            ),
            optimisticEntityIds: M.mediaOptimisticEntityIds + M.hueSyncOptimisticEntityIds,
            liveChangeEntityIds: [M.activeMediaSourceEntityId]
        )
    }()
}
