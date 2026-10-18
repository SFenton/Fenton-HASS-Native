import AppIntents
import FentonActivityModel

// A job card's buttons (`.agents/platforms/apple/live-activities-per-job.md` §7).
//
// This file is compiled into BOTH the app and the widget extension. The extension needs the type to draw
// `Button(intent:)`; a `LiveActivityIntent` runs in the app's process (the system launches the app in the background
// for it), so `perform()` only forwards to the handler the app installed at launch. In the extension no handler exists
// and nothing runs.

/// A card's button: Stop, Pause, Resume, Dock, Done. The engine maps the control id to a service; the phone never does.
struct JobControlIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Control Job"
    static let isDiscoverable = false

    @Parameter(title: "Activity")
    var tag: String

    @Parameter(title: "Control")
    var control: String

    init() {
        tag = HomeActivityAttributes.homeTag
        control = ""
    }

    init(tag: String, control: String) {
        self.tag = tag
        self.control = control
    }

    func perform() async throws -> some IntentResult {
        _ = await LiveActivityIntentRuntime.perform(.control(tag: tag, control: control))
        return .result()
    }
}
