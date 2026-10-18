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
    /// A room tile zooms into its room page (iOS 18 and later; a push before).
    @Namespace private var rooms

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                RoomOverviewGrid(kind: kind, zoomNamespace: rooms) { path.append($0) }
                    .padding(HassTokens.Spacing.l)
                    .frame(maxWidth: 960)
                    .frame(maxWidth: .infinity)
            }
            .modalChrome()
            // Direction G: the name centred, its state in the subtitle ("Lights", "3 of 12 On"). Before iOS 26, which
            // has no navigation subtitle, the title keeps the web's count.
            .navigationTitle(Self.title(kind, read: read))
            .inlineNavigationTitle()
            .sheetSubtitle(RoomOverview.sheetSubtitle(kind, read: read))
            .navigationDestination(for: RoomGroup.self) { group in
                RoomGroupDetailPage(kind: kind, group: group) { dismiss() }
                    .modalChrome()
                    .zoomDestination(id: group.room, in: rooms)
            }
            .toolbar {
                SheetCloseItem { dismiss() }
            }
        }
        .accessibilityIdentifier("overview.\(kind.rawValue)")
    }

    private func read(_ id: String) -> EntityState? { store.entity(id).state }

    /// The sheet's title: its name where the subtitle carries the state, else the web's title with its count.
    static func title(_ kind: RoomOverviewKind, read: RoomOverview.Read) -> String {
        SheetSubtitle.isShown ? RoomOverview.sheetName(kind) : RoomOverview.sheetTitle(kind, read: read)
    }
}
