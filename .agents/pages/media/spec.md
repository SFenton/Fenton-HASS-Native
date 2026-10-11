# Media

> **What:** platform-neutral spec for the Media page (web route `media`). **Read when:** changing Media on any platform.

Source: `ha-sfenton-react-dash@9ac2a46:src/pages/DashboardViewPage.tsx` `MediaPage` and `mediaPageCardFromItem` (2749-2867), `src/constants/portedDashboard.ts` `MEDIA_SECTIONS` (827), the Music Room's `lead-row` and `app-launch` source cards in `src/constants/roomPages.ts` (352-408), `src/constants/surfaceSemantics.ts` `MEDIA_PAGE_REMOTE_HASH_BY_ENTITY_ID` (83). Entry: Home Quick Links "Media" (`atAGlance.ts:257`).

Sections side by side when wide; each is a header, a full-width lead card, then a grid of the rest. Player cards are active on `on` and `playing`.

| Section | Card | Entity | Tap |
|---|---|---|---|
| Living Room | Living Room SHIELD (`mdi:television`, off icon `mdi:television-off`) | `media_player.living_room_shield` | Living Room SHIELD remote |
| Music Room | Music Room Remote | `media_player.music_room_tv_android` | Music Room remote |
| | Xbox (on for Xbox or Fortnite) | `sensor.music_room_active_media_source` | active: `script.music_room_tv_off`, else `script.music_room_xbox` |
| | Server | same | active: `script.music_room_tv_off`, else `script.music_room_server` |
| | Windows PC | same | active: `script.music_room_tv_off`, else `script.music_room_windows_pc` |
| | Fortnite (Quick App Launch) | same | `script.music_room_fortnite` |
| Theater Room | Theater Room | `media_player.sony_projector` | Theater Room SHIELD remote |
| | Nintendo Switch | `input_boolean.is_nintendo_switch_active` | `script.theater_room_nintendo_switch` (no target) |
| | Theater SHIELD | `input_boolean.is_theater_shield_active` | `script.theater_room_tv_movie` (no target) |

Music Room scripts carry the remote's optimistic intents (see [media-remote](../../patterns/media-remote.md)); the page and the Music Room remote share them. Source cards read "On" for their own source and "Off" otherwise. The Master Bedroom Apple TV is not on this page (web parity).
