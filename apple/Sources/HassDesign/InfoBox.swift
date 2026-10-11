import SwiftUI

/// A tinted notice with a title and optional message (pattern: `.agents/patterns/info-box.md`; web `InfoBox`).
///
/// Text stays in the primary label color on a light wash of the tone, so it keeps 4.5:1 in both appearances.
public struct InfoBox: View {
    /// The notice's tone.
    public enum Tone: Sendable {
        /// A confirmed, good state (green).
        case success
        /// Informational (gray).
        case neutral
    }

    public var title: String
    public var message: String?
    public var tone: Tone

    /// Creates a notice.
    public init(title: String, message: String? = nil, tone: Tone = .neutral) {
        self.title = title
        self.message = message
        self.tone = tone
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.xs) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: tone == .success ? "checkmark.circle.fill" : "info.circle.fill")
                    .foregroundStyle(tint)
            }
            .font(.headline)
            .foregroundStyle(HassTokens.Ink.primary)
            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(HassTokens.Ink.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(HassTokens.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: HassTokens.Radius.chip, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var tint: Color {
        switch tone {
        case .success: Color(red: 0.26, green: 0.63, blue: 0.28)
        case .neutral: .gray
        }
    }
}
