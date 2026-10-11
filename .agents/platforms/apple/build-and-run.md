# Build and run

> **What:** how to build, test and run the Apple apps. **Read when:** building or testing.

```bash
cd apple
swift test                  # Core, Design and hosted UI tests on the macOS host
xcodegen generate           # regenerates FentonHome.xcodeproj from project.yml (the project file is git-ignored)
xcodebuild -project FentonHome.xcodeproj -scheme FentonHome -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
```

- Coverage gate: `tools/apple_coverage.sh` (95% logic / 90% UX). Device journeys: `tools/ios_uitest.sh` ([devices](../../testing/apple/devices.md)).
- iPhone Duo APIs (`onHingeChange`, vertical bar) need the iOS 27.1 SDK; builds with an older SDK must add `FENTON_IOS_SDK_BEFORE_27_1` to `SWIFT_ACTIVE_COMPILATION_CONDITIONS`.
- Run one simulator at a time per host; never reset another project's devices.
- Keep the `UILaunchScreen` key and the `LaunchBackground` color asset, or older runtimes fall back to legacy compatibility frames (FestivalNativeApps finding).
