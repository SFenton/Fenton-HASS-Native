import HassCore
import HassDesign
import SwiftUI

/// One inventory card (web `PantryRow`; direction G mockup n6-inventory, redesigned 2026-10-16): the name over its expiry
/// line, then the stock count (above one) in secondary ink, the add-to-groceries cart in the action tint and, when the
/// card opens the item editor, a chevron.
///
/// Rows sit on the page's dense module (they carry orange and red expiry text). The whole row opens the editor;
/// swipe actions delete (single-batch items) and add to groceries. Multi-batch items delete from the editor.
struct InventoryRow: View {
    var item: InventoryDisplayItem
    var model: InventoryListModel
    var selected = false
    /// The row is the first on its module (top corners rounded).
    var isFirst = true
    /// The row is the last on its module (bottom corners rounded).
    var isLast = true
    var onEdit: () -> Void
    var onShop: () -> Void
    var onDelete: () -> Void

    @ScaledMetric(relativeTo: .body) private var buttonSize: CGFloat = 44
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The page's module is dark; in a sheet (the Summary's Expired Food tab) the card is the sheet's cell and the
    /// secondary ink follows the sheet.
    @Environment(\.tileSurface) private var surface

    var body: some View {
        let batches = model.batches(for: item).count
        let multiBatch = batches > 1
        let expiry = InventoryCatalog.expiryInfo(item.soonestExpiry(model.calendar), calendar: model.calendar)
        // The expiry alone: the stock count is the trailing number, so the line never grows long enough to push the
        // actions under the text (owner design pass, 2026-10-16: "pages look very rough right now").
        let subtitle = InventoryCatalog.rowSubtitle(expiry, quantity: nil, batchCount: batches)
        let deletable = model.deletableRows(of: item) != nil
        // Multi-batch cards always open the editor; a single batch needs row ids to edit.
        let opensEditor = multiBatch || deletable
        let tone = multiBatch ? nil : expiry.tone

        // Only accessibility sizes stack the actions under the text; `ViewThatFits` stacked them on every multi-batch row.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: HassTokens.Spacing.s))
            : AnyLayout(HStackLayout(spacing: HassTokens.Spacing.s))
        layout {
            copy(subtitle: subtitle, tone: tone)
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: HassTokens.Spacing.s) }
            HStack(spacing: HassTokens.Spacing.xs) {
                quantityLabel
                actions(opensEditor: opensEditor, multiBatch: multiBatch)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if opensEditor { onEdit() } }
        // The trailing inset is small so the chevron's 44 pt target ends near the module's edge (mockup).
        .listRowInsets(EdgeInsets(top: HassTokens.Spacing.s, leading: HassTokens.Spacing.l,
                                  bottom: HassTokens.Spacing.s, trailing: HassTokens.Spacing.xs))
        .listRowBackground(InventoryRowBackground(isFirst: isFirst, isLast: isLast, selected: selected))
        .listRowSeparatorTint(HassTokens.Surface.separator)
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

    /// Title 17 Regular, subtitle 15 in secondary, orange (soon) or red (expired) with a leading glyph.
    private func copy(subtitle: String, tone: ExpiryInfo.Tone?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.name)
                .font(.body)
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
            .foregroundStyle(InventoryTone.color(tone, surface: surface))
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

    /// The stock count, in secondary ink at the trailing edge like the counts on Reminders' lists; shown above one, as on
    /// the web (`itemQuantity`). VoiceOver hears it in the row's own label ("Quantity 3").
    @ViewBuilder
    private var quantityLabel: some View {
        if let quantity = item.shownQuantity {
            Text(InventoryFormat.quantity(quantity))
                .font(.body.monospacedDigit())
                .foregroundStyle(surface.secondaryInk)
                .padding(.trailing, HassTokens.Spacing.xs)
                .accessibilityHidden(true)
        }
    }

    private func accessibilityText(subtitle: String, tone: ExpiryInfo.Tone?) -> String {
        var parts = [item.name]
        if let quantity = item.shownQuantity { parts.append("Quantity \(InventoryFormat.quantity(quantity))") }
        parts.append(subtitle)
        if tone == .soon { parts.append("Expiring soon") }
        if let error = model.rowErrors[item.id] { parts.append(error) }
        return parts.joined(separator: ", ")
    }

    private func actions(opensEditor: Bool, multiBatch: Bool) -> some View {
        HStack(spacing: 0) {
            shoppingButton
            if opensEditor {
                // The visible chevron; the whole row opens the editor too. VoiceOver reaches the editor here.
                Button(action: onEdit) {
                    Image(systemName: "chevron.forward")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(surface.secondaryInk)
                        .frame(width: buttonSize, height: buttonSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Edit \(item.name)")
                .accessibilityHint(multiBatch ? "Opens each expiration batch" : "Opens the item editor")
                .accessibilityIdentifier("inventory.row.edit")
            }
        }
    }

    /// The cart glyph in the action tint (a quiet bare symbol: the grey circle on every row was visual noise), an arc while
    /// adding, a check once added. The 44 pt target stays.
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
                case .idle: Image(systemName: "cart.badge.plus").foregroundStyle(HassTokens.Ink.action)
                case .adding: ArcSpinner(.compact, label: "Adding to Groceries").foregroundStyle(HassTokens.Ink.primary)
                case .added: Image(systemName: "checkmark").foregroundStyle(InventoryTone.success)
                }
            }
            .font(.body)
            .frame(width: buttonSize, height: buttonSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(state != .idle)
        .accessibilityLabel(label)
        .accessibilityIdentifier("inventory.row.cart")
    }
}

/// A row's share of the page's dense module: the module tint (opaque with Reduce Transparency), rounded at the top of
/// the first row and the bottom of the last, with the split pane's selection washed over it.
struct InventoryRowBackground: View {
    var isFirst: Bool
    var isLast: Bool
    var selected: Bool
    @Environment(\.tileSurface) private var surface

    var body: some View {
        let radius = HassTokens.Radius.module
        // The dense module on the wallpaper, the sheet's cell colour in a sheet (as ``ModuleRowBackground`` does).
        ground
            .overlay {
                HassTokens.Ink.action.opacity(selected ? 0.18 : 0)
                    .stateColorTransition("InventoryRow", value: selected)
            }
            .clipShape(UnevenRoundedRectangle(
                topLeadingRadius: isFirst ? radius : 0, bottomLeadingRadius: isLast ? radius : 0,
                bottomTrailingRadius: isLast ? radius : 0, topTrailingRadius: isFirst ? radius : 0, style: .continuous
            ))
    }

    @ViewBuilder
    private var ground: some View {
        if surface == .sheet {
            HassTokens.Surface.sheetCell
        } else {
            Color.clear.module(.dense, cornerRadius: 0)
        }
    }
}

/// Expiry tone colours: G's orange `#FFB340` (soon) and red `#FF6961` (expired) on dark, from ``HassTokens/Ink``, which
/// keep 4.5:1 on the dense module and in sheets. A glyph carries the tone too, so colour isn't the only cue.
enum InventoryTone {
    static func color(_ tone: ExpiryInfo.Tone?, surface: TileSurface = .page) -> Color {
        switch tone {
        case .expired: HassTokens.Ink.error
        case .soon: HassTokens.Ink.warning
        case nil: surface.secondaryInk
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
