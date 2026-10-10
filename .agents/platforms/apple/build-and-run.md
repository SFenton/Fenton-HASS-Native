# Build and run

> **What:** how to build, test and run the Apple apps. **Read when:** building or testing.

```bash
cd apple
swift test                  # Core and Design unit tests on the macOS host
xcodegen generate           # regenerates FentonHome.xcodeproj from project.yml (the project file is git-ignored)
xcodebuild -project FentonHome.xcodeproj -scheme FentonHome -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
```

- Run one simulator at a time per host; never reset another project's devices.
- Keep the `UILaunchScreen` key and the `LaunchBackground` color asset, or older runtimes fall back to legacy compatibility frames (FestivalNativeApps finding).
