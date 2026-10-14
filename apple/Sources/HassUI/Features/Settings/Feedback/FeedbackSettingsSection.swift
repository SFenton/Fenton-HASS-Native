import HassCore
import HassDesign
import SwiftUI

/// The Settings list's Feedback section: Report an Issue and Request a Feature, each opening
/// ``FeedbackFormSheet``. Reports land in the private request repository, where the triage agent on the
/// MacBook picks them up (`.agents/workflow/triage-agent.md`).
struct FeedbackSettingsSection: View {
    @Binding var openForm: FeedbackKind?

    var body: some View {
        Section {
            ForEach(FeedbackKind.allCases) { kind in
                Button { openForm = kind } label: {
                    SettingsLinkRow(title: kind.formTitle, subtitle: kind.rowSubtitle, symbol: kind.symbol)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.feedback.\(kind.rawValue)")
                .accessibilityHint("Opens a form that files it on GitHub.")
            }
        }
        // No section header: the list sits on the house backdrop (page-backdrop R4), where a bare header measured
        // 1.2:1 on iPad; the rows' own titles say what they do, like the Performance section above.
    }
}

extension View {
    /// Presents the feedback form for `kind` through ``SwiftUI/View/hassSheet(_:)`` (full height on iPhone, a form sheet on iPad), deleting staged media however it closes.
    func feedbackFormSheet(item kind: Binding<FeedbackKind?>) -> some View {
        sheet(item: kind, onDismiss: FeedbackFormModel.purgeStagedMedia) { kind in
            FeedbackFormSheet(kind: kind)
                .hassSheet(.form)
        }
    }
}
