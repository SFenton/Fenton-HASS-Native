import HassCore
import HassDesign
import SwiftUI

/// One inventory card (web `PantryRow`): name, `Quantity · Expires on …`, and its actions.
///
/// Single-batch items get cart, edit and delete buttons; multi-batch items get cart and a disclosure that
/// opens the editor, and the whole row opens it too. Swipe actions repeat delete and add-to-groceries.
struct InventoryRow: View {
    var item: InventoryDisplayItem
    var model: InventoryListModel
    var selected = false
    var onEdit: () -> Void
    var onShop: () -> Void
    var onDelete: () -> Void

    @ScaledMetric(relativeTo: .body) private var buttonSize: CGFloat = 44

    var body: some View {
        let batches = model.batches(for: item).count
        let multiBatch = batches > 1
        let expiry = InventoryCatalog.expiryInfo(item.soonestExpiry(model.calendar), calendar: model.calendar)
        let subtitle = InventoryCatalog.rowSubtitle(expiry, quantity: item.shownQuantity, batchCount: batches)
        let deletable = model.deletableRows(of: item) != nil
        let tone = multiBatch ? nil : expiry.tone

        ViewThatFits(in: .horizontal) {
            HStack(spacing: HassTokens.Spacing.s) {
                copy(subtitle: subtitle, tone: tone)
                Spacer(minLength: HassTokens.Spacing.s)
                actions(multiBatch: multiBatch, deletable: deletable)
            }
            // AX sizes: actions wrap under the text instead of squeezing it.
            VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
                copy(subtitle: subtitle, tone: tone)
                actions(multiBatch: multiBatch, deletable: deletable)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if multiBatch { onEdit() } }
        .listRowBackground(selected ? Color.accentColor.opacity(0.14) : nil)
        .swipeActions(edge: .trailing) {
            if deletable && !multiBatch {
                Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
            }
        }
        .swipeActions(edge: .leading) {
            Button("Add to Groceries", systemImage: "cart.badge.plus", action: onShop)
                .tint(FloatingActionBar.tint)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inventory.row.\(item.name)")
    }

    // MARK: - Parts

    private func copy(subtitle: String, tone: ExpiryInfo.Tone?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.name)
                .font(.body.weight(.semibold))
                .foregroundStyle(HassTokens.Ink.primary)
                .fixedSize(horizontal: false, vertical: true)
                .privacySensitive()
            HStack(alignment: .firstTextBaseline, spacing: HassTokens.Spacing.xs) {
                if let tone {
                    Image(systemName: tone == .expired ? "exclamationmark.triangle.fill" : "clock.fill")
                        .imageScale(.small)
                        .accessibilityHidden(true)
                }
                Text(subtitle)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(InventoryTone.color(tone))
            if let error = model.rowErrors[item.id] {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(InventoryTone.color(.expired))
                    .accessibilityIdentifier("inventory.row.error")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText(subtitle: subtitle, tone: tone))
    }

    private func accessibilityText(subtitle: String, tone: ExpiryInfo.Tone?) -> String {
        var parts = [item.name, subtitle]
        if tone == .soon { parts.append("Expiring soon") }
        if let error = model.rowErrors[item.id] { parts.append(error) }
        return parts.joined(separator: ", ")
    }

    @ViewBuilder
    private func actions(multiBatch: Bool, deletable: Bool) -> some View {
        HStack(spacing: HassTokens.Spacing.xs) {
            shoppingButton
            if multiBatch {
                iconButton("chevron.right", label: "Edit \(item.name)", id: "edit", action: onEdit)
                    .accessibilityHint("Opens each expiration batch")
            } else {
                iconButton("pencil", label: "Edit \(item.name)", id: "edit", action: onEdit)
                    .disabled(!deletable)
                deleteButton(deletable: deletable)
            }
        }
    }

    private var shoppingButton: some View {
        let state = model.shopping[item.id, default: .idle]
        let label = switch state {
        case .idle: "Add \(item.name) to shopping list"
        case .adding: "Adding \(item.name) to shopping list"
        case .added: "Added \(item.name) to shopping list"
        }
        return Button(action: onShop) {
            ZStack {
                switch state {
                case .idle: Image(systemName: "cart.badge.plus")
                case .adding: ProgressView()
                case .added: Image(systemName: "checkmark").foregroundStyle(InventoryTone.success)
                }
            }
            .frame(width: buttonSize, height: buttonSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(state != .idle)
        .accessibilityLabel(label)
        .accessibilityIdentifier("inventory.row.cart")
    }

    private func deleteButton(deletable: Bool) -> some View {
        let deleting = model.deleting.contains(item.id)
        return Button(action: onDelete) {
            ZStack {
                if deleting { ProgressView() } else { Image(systemName: "trash") }
            }
            .frame(width: buttonSize, height: buttonSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(InventoryTone.color(.expired))
        .disabled(deleting || !deletable)
        .accessibilityLabel(deleting ? "Deleting \(item.name)" : "Delete \(item.name)")
        .accessibilityIdentifier("inventory.row.delete")
    }

    private func iconButton(_ symbol: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: buttonSize, height: buttonSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(label)
        .accessibilityIdentifier("inventory.row.\(id)")
    }
}

/// Expiry tone colors that hold 4.5:1 on grouped list rows in light and dark mode (system red and orange
/// measure about 4:1 and 2.5:1 on white). An icon carries the tone too, so color isn't the only cue.
enum InventoryTone {
    static func color(_ tone: ExpiryInfo.Tone?) -> Color {
        switch tone {
        case .expired: dynamic(light: (0.70, 0.11, 0.09), dark: (1.0, 0.54, 0.50))
        case .soon: dynamic(light: (0.54, 0.29, 0.0), dark: (1.0, 0.72, 0.30))
        case nil: HassTokens.Ink.secondary
        }
    }

    static let success = dynamic(light: (0.11, 0.45, 0.17), dark: (0.45, 0.85, 0.50))

    private static func dynamic(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        #if canImport(UIKit)
        Color(uiColor: UIColor { traits in
            let rgb = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        })
        #else
        Color(red: light.0, green: light.1, blue: light.2)
        #endif
    }
}
