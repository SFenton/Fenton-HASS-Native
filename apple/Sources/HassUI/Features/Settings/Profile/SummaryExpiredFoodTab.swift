import HassCore
import HassDesign
import SwiftUI

/// The Summary sheet's Expired Food tab (web `DailyReportExpiredFoodTab`).
///
/// The sensor `sensor.evershelf_expired_items` decides whether there is anything to show (its `expired_list` counts items
/// past their date on the local calendar, ``ProfileSummary/expiredFoodCount(_:now:calendar:)``). The rows are the Food
/// page's own: the All Food model's expired items, soonest expiry first, drawn by the canonical ``InventoryRow`` (name, a
/// red "Expired N Days Ago" with the warning glyph, the stock count above one, the add-to-Groceries cart and a chevron
/// into the same item editor) with the same swipe actions. The web does the same by locking the Food page's controls to
/// the expired filter.
///
/// Vacation Mode hides the list ("Expired Food Hidden", or "No Expired Food" when the count is a confirmed zero, with
/// "Enjoy vacation!"): nothing in the kitchen can be dealt with from away.
struct SummaryExpiredFoodTab: View {
    var store: EntityStore
    @Environment(\.inventoryModels) private var injected
    @Environment(HassConnection.self) private var connection: HassConnection?
    @State private var holder = InventoryModelsHolder()

    var body: some View {
        let vacation = store.entity(ChoresConfig.vacationModeEntityId).state?.state == "on"
        let sensor = store.entity(ProfileSummary.expiredFoodEntityId).state
        let count = ProfileSummary.expiredFoodCount(sensor)
        if let empty = ProfileSummary.expiredFoodEmpty(count: count, vacationMode: vacation) {
            List {
                SummaryEmptyState(copy: empty, symbol: vacation ? "airplane" : "checkmark.circle", identifier: "summary.empty.expired-food")
                    .modifier(TodoPlainRow(top: HassTokens.Spacing.m, bottom: 0))
            }
            .accessibilityIdentifier("summary.expired-food")
        } else if let models = injected ?? connection.map(holder.models(for:)) {
            ExpiredFoodList(model: models.model(for: .allFood), sensor: sensor)
        } else {
            Color.clear
        }
    }
}
