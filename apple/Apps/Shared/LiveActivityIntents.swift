import AppIntents
import FentonActivityModel

// The Home Live Activity's buttons (`.agents/platforms/apple/live-activities.md` §5).
//
// This file is compiled into BOTH the app and the widget extension. The extension needs the types to draw
// `Button(intent:)`; a `LiveActivityIntent` runs in the app's process (the system launches the app in the background
// for it), so `perform()` only forwards to the handler the app installed at launch. In the extension no handler exists
// and nothing runs.

/// ‹ and ›: show another job in the Dynamic Island and offer its controls.
struct FocusJobIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Show Job"
    static let isDiscoverable = false

    @Parameter(title: "Activity")
    var tag: String

    @Parameter(title: "Job")
    var job: String

    init() {
        tag = HomeActivityAttributes.homeTag
        job = ""
    }

    init(tag: String, job: String) {
        self.tag = tag
        self.job = job
    }

    func perform() async throws -> some IntentResult {
        _ = await LiveActivityIntentRuntime.perform(.focus(tag: tag, job: job))
        return .result()
    }
}

/// A job's button: Stop, Resume, Cancel Timer.
struct JobControlIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Control Job"
    static let isDiscoverable = false

    @Parameter(title: "Activity")
    var tag: String

    @Parameter(title: "Job")
    var job: String

    @Parameter(title: "Control")
    var control: String

    init() {
        tag = HomeActivityAttributes.homeTag
        job = ""
        control = ""
    }

    init(tag: String, job: String, control: String) {
        self.tag = tag
        self.job = job
        self.control = control
    }

    func perform() async throws -> some IntentResult {
        _ = await LiveActivityIntentRuntime.perform(.control(tag: tag, job: job, control: control))
        return .result()
    }
}
