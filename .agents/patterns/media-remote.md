# Media remote

> **What:** the media remote sheet (power, d-pad, Controls/Apps/Devices/Hue Sync tabs) shared by every TV in the house. **Read when:** opening a remote from any screen, adding a remote, or changing remote controls.

Web source: `ha-sfenton-react-dash@9ac2a46:src/components/hass/MediaRemoteModalContent.tsx`, `src/constants/mediaRemotes.ts`.

| Piece | File |
|---|---|
| Config model | `HassCore/Config/MediaRemoteConfig.swift` |
| The four remotes (Living Room SHIELD, Master Bedroom Apple TV, Theater Room SHIELD, Music Room) | `HassCore/Config/MediaRemotes.swift` |
| Action resolution, state helpers | `HassCore/MediaRemote/MediaRemoteLogic.swift` |
| Optimistic overlay, active hold, revert scheduler | `HassCore/Entities/OptimisticOverlay.swift` |
| Controller (reads, actions, Hue Sync) | `HassCore/MediaRemote/MediaRemoteController.swift` |
| Service seam (`HassServiceCalling`; `HassConnection` conforms) | `HassCore/MediaRemote/HassServiceCalling.swift` |
| Sheet and layout policy | `HassUI/Features/MediaRemote/MediaRemoteSheet.swift` |
| Power pill, d-pad, round buttons, Controls tab | `HassUI/Features/MediaRemote/MediaRemoteControls.swift` |
| Apps, Devices, Hue Sync tabs | `HassUI/Features/MediaRemote/MediaRemoteTabs.swift` |
| Debug gallery page (`FENTON_GALLERY=media-remote`) | `HassUI/Features/Gallery/MediaRemoteGallery.swift` |

## Using it

```swift
.sheet(item: $remote) { config in
    MediaRemoteSheet(config: config, connection: connection)
        .mediaRemotePresentation()   // .large, drag indicator, page sizing on iPad
}
```

`MediaRemotes.config(forMediaPlayer:)` maps a media player to its remote (web `MEDIA_PAGE_REMOTE_HASH_BY_ENTITY_ID`).

## Rules

- **Service calls are verbatim from the web.** Configs hold `ServiceCall`s; `target` goes out as `entity_id`. The keyboard sends `androidtv.adb_command` to the media player with `input text '<text>'`, each `'` written `'\''` (the web's `submitTextPrompt`; the brief said `remote.send_command`, the web wins). Blank text sends nothing.
- **State actions** (`.state`) decide from the displayed (optimistic, else live) state of the action's entity, else the control's entity; a device with a `stateResolver` decides from its resolved, held state.
- **Optimistic values** exist only for `optimisticEntityIds` (Music Room). They clear on confirmation (`liveChangeEntityIds`: on any live change), on a failed call (by generation), or after the intent's revert time. Volume has its own 2.5 s overlay; Hue Sync intents revert after 8 s.
- **Xbox hold:** the Music Room Xbox tile keeps showing `on` for 45 s after its resolved live state drops, unless an optimistic value shows or one of its reset entities changes (web `useHeldDeviceState`).
- **Disabled:** d-pad, navigation and playback when the control entity is off, unavailable or unknown; volume when the volume entity is off or unavailable. The volume section shows while the speaker is on, or always with `showVolumeWhenOff` (if the entity exists). App tiles with a state entity disable while it is unavailable; actionable devices disable while unavailable.
- **Power:** pill with "Power On"/"Power Off" text; icon red while on, green while every rule entity is in its inactive states. VoiceOver label is the config label ("Power"); the value is On/Off; it is a switch only where the config gives toggle semantics (Music Room).
- **Tabs:** only those with content (`MediaRemoteConfig.tabs`). Segmented control; a menu at accessibility text sizes.
- **Layout:** two columns (power and d-pad leading, tab content trailing, 50/50 so the Duo hinge falls between them) only when `SplitPolicy` allows a split for the *window* and the sheet is ≥ 640 pt wide; one scrolling column everywhere else. Never a device-name check.
- **Accessibility:** d-pad group labeled "<title> remote controls"; buttons use their config labels; light haptic per d-pad press; ≥ 44 pt targets (d-pad 64–104 pt, round buttons 44–88 pt, scaled with Dynamic Type); app tiles, sync modes, intensity and HDMI tiles carry `.isSelected`; Hue Sync toggles and toggle devices read On/Off; read-only devices are not buttons; the keyboard button reads Expanded/Collapsed.
- **Sliders** commit on release, or at once for steps without a drag (VoiceOver adjust), instead of one call per point.
- `GlassTile` has no selection/state kind yet; `RemoteGlassTile` adds the traits around it. TODO(orchestrator): fold `.selection` and `.state` into `GlassTile.Kind`.
- Fortnite artwork is bundled in the web build, not on the server; the tile shows its icon until `/local/images/apps/fortnite.jpg` exists.

## Tests

Findings from the device runs (2026-10-11):

- Only one keyboard layout at a time: a `ViewThatFits` kept the unused variant's Send button in the accessibility tree, and XCUITest matched the hidden copy. Choose the layout with `AnyLayout` (row; stacked at accessibility sizes).
- A blank button label (`EmptyView`) collapses the round button to 0 pt; draw `Color.clear`.
- `GlassTile`'s `.disabled` sits inside its combined accessibility element, so unavailable tiles read as enabled; `RemoteGlassTile` applies `.disabled` again outside.
- At AX5 in two columns the d-pad is capped to its column (never under 44 pt).
- Journeys scroll with short drags in screen points anchored on the window, at the element's x, clear of the Duo's trailing vertical bar: `app.coordinate` gestures never reach the unfolded Duo's inner display, normalized coordinates stay portrait in landscape, and in two columns each side scrolls on its own.
- The unfolded Duo's inner panel boots in landscape; rotate in Device Hub for unfolded portrait.

- Unit (`HassCoreTests/MediaRemote*Tests.swift`): configs vs web, `.state` cases, Xbox resolver, text escaping, power color rule, disabled/visibility rules, optimistic commit/confirm/revert/failure, holds, Hue Sync.
- Hosted (`HassUITests/MediaRemoteViewTests.swift`): every remote × tab in one and two columns, AX5, all unavailable; layout policy; every mapped SF Symbol exists; keyboard and slider state.
- Device (`iOSUITests/MediaRemoteJourneyTests.swift`, gallery fixtures with a recording caller, never the house): calls sent, semantics, 44 pt targets, layout per pose, audits per tab (iPad both orientations) with the AX5 relaunch, screenshots.
