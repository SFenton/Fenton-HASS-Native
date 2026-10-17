import FentonActivityModel
import Foundation

/// Runs the Home activity's button presses in the app process (`live-activities.md` §5).
///
/// - **‹ ›** (``LiveActivityAction/focus(tag:job:)``): focuses the job locally at once, then tells Home Assistant
///   (`fenton_live_activity_focus`) so the engine keeps that focus for this device in later pushes.
/// - **A job control** (``LiveActivityAction/control(tag:job:control:)``): shows the job as "Stopping…" with its
///   buttons hidden, fires `fenton_live_activity_action` over the registration webhook, and on failure puts the
///   buttons back with "Couldn't reach Home". Home Assistant checks the control and the caller, calls the service
///   and pushes the confirmed state, which replaces the optimistic one.
///
/// The Phase 1 control events are answered by an automation the owner applies
/// (`.agents/platforms/apple/live-activities-ha-automations.md`); the Phase 2 engine takes over.
public struct HomeActivityActionHandler: LiveActivityIntentRuntime.Handler {
    private let client: any LiveActivityClient
    private let webhook: @Sendable () -> (any LiveActivityWebhookSending)?

    /// Creates a handler.
    /// - Parameters:
    ///   - client: ActivityKit.
    ///   - webhook: The signed-in registration's webhook sender, read when the press happens; nil while signed out.
    public init(client: any LiveActivityClient, webhook: @escaping @Sendable () -> (any LiveActivityWebhookSending)?) {
        self.client = client
        self.webhook = webhook
    }

    /// Shown on a job after a control could not reach Home Assistant.
    public static let failureStatus = "Couldn't reach Home"

    public func handle(_ action: LiveActivityAction) async -> Bool {
        let records = await client.current()
        guard let record = records.first(where: { $0.tag == action.tag && $0.lifecycle.isLive }) else { return false }
        switch action {
        case let .focus(_, job):
            return await focus(job, in: record)
        case let .control(_, job, control):
            return await perform(control, on: job, in: record)
        }
    }

    private func focus(_ job: String, in record: LiveActivityRecord) async -> Bool {
        var state = record.state.focusing(job)
        guard state != record.state else { return true }
        if let focused = state.focusedJob { state.url = HomeJobDeriver.url(for: focused) }
        await client.update(id: record.id, state: state, staleDate: nil)
        try? await webhook()?.fireEvent(LiveActivityEventType.focus, data: ["tag": record.tag, "job": job])
        return true
    }

    private func perform(_ control: String, on jobID: String, in record: LiveActivityRecord) async -> Bool {
        guard let original = record.state.jobs.first(where: { $0.id == jobID }),
              original.controls.contains(where: { $0.id == control }) else { return false }
        await client.update(id: record.id, state: record.state.stopping(jobID), staleDate: nil)
        do {
            guard let webhook = webhook() else { throw MobileAppWebhookError.notRegistered }
            try await webhook.fireEvent(LiveActivityEventType.action, data: ["tag": record.tag, "job": jobID, "control": control])
            return true
        } catch {
            var restored = original
            restored.status = Self.failureStatus
            await client.update(id: record.id, state: record.state.restoring(restored), staleDate: nil)
            return false
        }
    }
}
