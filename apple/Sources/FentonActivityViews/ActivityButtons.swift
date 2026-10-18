import FentonActivityModel
import SwiftUI

/// A card's buttons: up to two pills (three on a problem card), the first white and the rest dark, each a 44 pt target
/// named for its device ("Stop Guest Bath Fan"). While a press waits for Home Assistant the pills give way to its label
/// ("Stopping…"); once that state is stale they return with a small "Not confirmed" beside them.
struct ActivityButtons: View {
    let card: ActivityCard
    /// The buttons to draw (the island draws two).
    let buttons: [ActivityCard.Button]
    /// Chips for the leading side of the row (a problem card's "Error 88").
    var chips: [String] = []
    @Environment(\.activityActions) private var actions
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if let label = card.pendingLabel {
            HStack(spacing: 8) {
                chipRow
                Spacer(minLength: 0)
                Text(label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ActivityStyle.secondaryText)
                    .lineLimit(1)
                    .frame(minHeight: ActivityStyle.minimumHit)
                    .accessibilityIdentifier("liveactivity.pending")
            }
        } else if !buttons.isEmpty || !chips.isEmpty || card.isUnconfirmed {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .trailing, spacing: 4) {
                    status
                    ForEach(buttons) { button in pill(button) }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                HStack(spacing: 8) {
                    chipRow
                    status
                    Spacer(minLength: 0)
                    ForEach(buttons) { button in pill(button) }
                }
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        if card.isUnconfirmed {
            Text(ActivityCard.unconfirmedText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(ActivityStyle.secondaryText)
                .lineLimit(1)
                .accessibilityIdentifier("liveactivity.unconfirmed")
        }
    }

    @ViewBuilder
    private var chipRow: some View {
        ForEach(chips, id: \.self) { chip in
            Text(chip)
                .font(.caption.weight(.semibold))
                .foregroundStyle(ActivityStyle.primaryText)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(ActivityStyle.secondaryButtonFill))
                // The problem's spoken summary already reads the chip.
                .accessibilityHidden(true)
        }
    }

    private func pill(_ button: ActivityCard.Button) -> some View {
        actions.control(card.tag, button.control, AnyView(label(button)))
            .accessibilityLabel(button.accessibilityLabel)
    }

    private func label(_ button: ActivityCard.Button) -> some View {
        Text(button.control.title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(button.isPrimary ? ActivityStyle.primaryButtonText : ActivityStyle.primaryText)
            .lineLimit(1)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(minHeight: ActivityStyle.buttonHeight)
            .background(Capsule().fill(button.isPrimary ? ActivityStyle.primaryButtonFill : ActivityStyle.secondaryButtonFill))
            .frame(minWidth: ActivityStyle.minimumHit, minHeight: ActivityStyle.minimumHit)
            .contentShape(Rectangle())
    }
}
