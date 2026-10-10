# Fenton HASS Native

Native iOS, iPadOS and watchOS apps for the Fenton household's Home Assistant (`https://homeassistant.sfenton-server.com`), modeled on the React dashboard in [`SFenton/ha-sfenton-react-dash`](https://github.com/SFenton/ha-sfenton-react-dash). Built with SwiftUI on top of [HAKit](https://github.com/home-assistant/HAKit).

**Status:** scaffold. Sign-in, the websocket connection, the cached entity store and the Home screen exist; other tabs are placeholders.

## Build

Requires Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
cd apple
swift test                 # HassCore and HassDesign unit tests (macOS host)
xcodegen generate          # writes FentonHome.xcodeproj
open FentonHome.xcodeproj  # run the FentonHome scheme on an iPhone or iPad simulator
```

## Where to start

- [Agent entry point and invariants](AGENTS.md)
- [Knowledge router](.agents/README.md)
- [Plan, lanes and progress](PROGRESS.md)
