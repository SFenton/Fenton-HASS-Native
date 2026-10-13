import Foundation

/// The GitHub issue a report becomes: title, Markdown body and labels.
public struct FeedbackIssue: Sendable, Equatable {
    public var title: String
    public var body: String
    public var labels: [String]

    /// Hidden marker ending every in-app report, so the triage agent can tell app reports from issues
    /// typed on GitHub. Text a person typed can't forge it (``escaped(_:)``).
    public static let marker = "<!-- fenton-feedback:v1 -->"
    /// Label on every in-app report.
    public static let fromAppLabel = "From App"

    /// Creates an issue.
    public init(title: String, body: String, labels: [String]) {
        self.title = title
        self.body = body
        self.labels = labels
    }

    /// Composes the issue for a draft.
    ///
    /// - Parameters:
    ///   - draft: A valid draft.
    ///   - platform: Device family label.
    ///   - diagnostics: Device, app and Home Assistant details.
    ///   - media: Uploaded attachments in order, with their GitHub URLs.
    /// - Returns: The issue: `[Bug] title`, sections for each filled box, media, a diagnostics table and
    ///   the marker; labels `Bug`/`Feature`, `From App` and the platform.
    public static func compose(
        draft: FeedbackDraft, platform: FeedbackPlatform, diagnostics: FeedbackDiagnostics,
        media: [(attachment: FeedbackAttachment, url: URL)]
    ) -> FeedbackIssue {
        var sections: [String] = []
        func add(_ heading: String, _ text: String) {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return }
            sections.append("### \(heading)\n\n\(escaped(value))")
        }
        add("Description", draft.description)
        if draft.kind.includesReproduction {
            add("Steps to Reproduce", draft.reproSteps)
            add("Expected Behavior", draft.expectedBehavior)
        }
        if !media.isEmpty {
            // GitHub renders a user-attachment video URL on its own line as a player.
            let lines = media.map { item in
                item.attachment.isVideo
                    ? item.url.absoluteString
                    : "![\(item.attachment.filename)](\(item.url.absoluteString))"
            }
            sections.append("### Media\n\n" + lines.joined(separator: "\n\n"))
        }
        let rows = diagnostics.rows.map { "| \($0.label) | \(tableCell($0.value)) |" }
        sections.append("### Diagnostics\n\n| | |\n|---|---|\n" + rows.joined(separator: "\n"))
        sections.append("<sub>Filed from the app's Settings.</sub>\n\(marker)")
        return FeedbackIssue(
            title: oneLine(draft.kind.titlePrefix + draft.titleBody),
            body: sections.joined(separator: "\n\n"),
            labels: [draft.kind.label, fromAppLabel, platform.label]
        )
    }

    /// Escapes HTML comment openers so typed text can't hide content or forge the marker.
    static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "<!--", with: "&lt;!--")
    }

    /// A value safe inside a Markdown table cell.
    static func tableCell(_ text: String) -> String {
        escaped(oneLine(text)).replacingOccurrences(of: "|", with: "\\|")
    }

    /// Collapses whitespace and newlines to single spaces.
    static func oneLine(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
    }
}
