import Foundation

/// Debug-only redaction for screenshots shared outside the household: `FENTON_REDACT_PRIVATE=1` blurs
/// camera snapshots, hides the security and occupancy summaries, and redacts live inventory item names.
/// Always off in release builds.
enum ScreenshotPrivacy {
    static let isRedacting: Bool = {
        #if DEBUG
        ProcessInfo.processInfo.environment["FENTON_REDACT_PRIVATE"] == "1"
        #else
        false
        #endif
    }()
}
