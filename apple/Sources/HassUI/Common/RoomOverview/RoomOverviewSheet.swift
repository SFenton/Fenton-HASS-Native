import HassCore
import HassDesign
import SwiftUI

/// A room-by-room overview sheet that pushes a room's detail page (web `LightsSheet`, `ClimateSheet`,
/// `OccupancySheet`, `ContactSheet` and `AirQualitySheet` in `ha-sfenton-react-dash@f5a7bf9:src/pages/AtAGlancePage.tsx`;
/// pattern: `.agents/patterns/room-overview-sheet.md`).
///
/// Home opens it from five status chips and the Security page from its Contact Sensors chip. A room tap pushes the
/// room inside the sheet's own `NavigationStack` with Back, as the web's in-sheet back button does (HIG: Sheets,
/// "a sheet can contain a navigation hierarchy").
struct RoomOverviewSheet: View {
    var kind: RoomOverviewKind
    @Environment(EntityStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var path: [RoomGroup] = []

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                RoomOverviewGrid(kind: kind) { path.append($0) }
                    .padding(HassTokens.Spacing.l)
                    .frame(maxWidth: 960)
                    .frame(maxWidth: .infinity)
            }
            .navigationTitle(RoomOverview.sheetTitle(kind, read: read))
            .inlineNavigationTitle()
            .navigationDestination(for: RoomGroup.self) { group in
                RoomGroupDetailPage(kind: kind, group: group) { dismiss() }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .accessibilityIdentifier("overview.\(kind.rawValue)")
    }

    private func read(_ id: String) -> EntityState? { store.entity(id).state }
}
