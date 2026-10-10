# Apple testing

> **What:** what to test and when on Apple platforms. **Read when:** adding or changing Swift code.

| Phase | Tests |
|---|---|
| Feature build | Unit tests for `HassCore` and `HassDesign` logic (`swift test`); quick simulator screenshots |
| Feature complete | XCUITests per page, accessibility checks (labels, traits, Dynamic Type, 44 pt targets) |
| Release | Whole-app audits and VoiceOver walkthroughs |

- Network code is tested with `URLProtocol` stubs; never hit the live server from automated tests.
- `EntityStore` tests assert that unchanged entities keep the same box and are not re-published.
