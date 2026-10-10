import Foundation

/// Debug-only redaction for screenshots shared outside the household: `FENTON_REDACT_PRIVATE=1` blurs
/// camera snapshots and hides the security and occupancy summaries. Always off in release builds.
enum ScreenshotPrivacy {
    static let isRedacting: Bool = {
        #if DEBUG
        ProcessInfo.processInfo.environment["FENTON_REDACT_PRIVATE"] == "1"
        #else
        false
        #endif
    }()
}
