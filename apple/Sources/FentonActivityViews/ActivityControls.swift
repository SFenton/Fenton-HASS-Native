import FentonActivityModel
import SwiftUI

/// A job's one or two buttons ("Stop", "Cancel Timer"), each named for its job ("Stop Dishwasher"); "Stopping…" in
/// place of them while Home Assistant has not confirmed a press.
struct ActivityControls: View {
    let job: ActivityJob
    let tag: String
    @Environment(\.activityActions) private var actions

    var body: some View {
        if job.phase == .stopping {
            Text("Stopping…")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ActivityStyle.secondaryText)
                .frame(minHeight: ActivityStyle.minimumHit)
        } else {
            HStack(spacing: 8) {
                ForEach(job.controls) { control in
                    actions.control(tag, job, control, AnyView(label(control)))
                        .accessibilityLabel("\(control.title) \(job.title)")
                }
            }
        }
    }

    private func label(_ control: ActivityControl) -> some View {
        Text(control.title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(control.role == .destructive ? ActivityStyle.destructive : ActivityStyle.primaryText)
            .lineLimit(1)
            .padding(.horizontal, 14)
            .frame(minHeight: ActivityStyle.minimumHit)
            .background(Capsule().fill(Color.white.opacity(0.14)))
            .contentShape(Capsule())
    }
}
