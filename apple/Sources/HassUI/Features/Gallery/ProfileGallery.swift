#if DEBUG
import Foundation
import HassCore
import HassDesign
import SwiftUI

/// Gallery page for the Your Summary sheet (the header Profile button): presents it as the app does, over a plain page,
/// on fixtures with a recording service, so journeys, audits and screenshots reach every tab without touching the house.
/// Check-offs, edits and deletes land on the fixture services and are shown on the `Last call` line, never on Home Assistant.
///
/// Environment (all optional):
/// - `FENTON_GALLERY_VIEWER=stephen|steph|guest` (default `stephen`): who is signed in; a guest is not a resident.
/// - `FENTON_GALLERY_TAB=profile|overdue|upcoming|expired-food`: the tab to open on (default the viewer's).
/// - `FENTON_GALLERY_VACATION=1`: Vacation Mode is on.
/// - `FENTON_GALLERY_EMPTY=1`: every chore list and the pantry are empty.
/// - `FENTON_GALLERY_CHORES=<n>`: `n` more chores per Stephen list.
/// - `FENTON_GALLERY_CLEAN=1`: hides the last-call line (screenshots).
struct ProfileGallery: View {
    @State private var store: EntityStore
    @State private var chores: ChoresModel
    @State private var service: ChoresFixtureService
    @State private var server: EverShelfFixtureServer
    @State private var models: InventoryModels
    @State private var navigator: ShellNavigator
    private let opening: SummaryTab?

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        let empty = environment["FENTON_GALLERY_EMPTY"] == "1"
        let viewerName = environment["FENTON_GALLERY_VIEWER"] ?? "stephen"
        let viewer = ChoresConfig.Resident(rawValue: viewerName)
        let store = EntityStore()
        let service = ChoresFixtureService(
            store: store, lists: empty ? [:] : ChoresFixtures.lists(extra: Int(environment["FENTON_GALLERY_CHORES"] ?? "") ?? 0)
        )
        let server = EverShelfFixtureServer.sample()
        Self.addExpiredFood(to: server)
        if empty { server.rows = [] }
        server.latency = .milliseconds(environment["FENTON_GALLERY_LATENCY_MS"].flatMap { Int($0) } ?? 100)
        service.extraStates = Self.people() + [
            EntityState(entityId: ChoresConfig.vacationModeEntityId, state: environment["FENTON_GALLERY_VACATION"] == "1" ? "on" : "off"),
            Self.expiredFoodSensor(server.rows),
        ]
        store.replaceAll(service.entityStates())
        let navigator = ShellNavigator()
        navigator.profileName = viewer.map { $0 == .stephen ? "Stephen Fenton" : "Steph Fenton" } ?? "Guest"
        _store = State(initialValue: store)
        _service = State(initialValue: service)
        _server = State(initialValue: server)
        _models = State(initialValue: InventoryModels(client: EverShelfClient(caller: server)))
        _navigator = State(initialValue: navigator)
        _chores = State(initialValue: ChoresModel(service: service, todos: TodoStore(service: service), viewerUserId: viewer?.haUserId))
        opening = environment["FENTON_GALLERY_TAB"].flatMap(SummaryTab.init(rawValue:))
    }

    var body: some View {
        // A blank presenting page, as the other sheet galleries have: text beside a page sheet is hidden from VoiceOver by the
        // modal, and the audit reports it as potentially inaccessible.
        Color.black
            .ignoresSafeArea()
            .preferredColorScheme(.dark)
            .sheet(isPresented: .constant(true)) {
                YourSummarySheet(opening: opening)
                    .environment(store)
                    .environment(chores)
                    .environment(navigator)
                    .environment(\.inventoryModels, models)
                    .safeAreaInset(edge: .top, spacing: 0) {
                        if !GalleryEnvironment.isClean {
                            GalleryLastCall(text: lastCall)
                                .padding(.horizontal)
                                .padding(.vertical, 4)
                        }
                    }
                    .hassSheet(.form, height: .full)
            }
    }

    /// The chore service's last call, else the kitchen's.
    private var lastCall: String {
        service.lastCall == "none" ? server.lastCall.replacing("None", with: "none") : service.lastCall
    }

    // MARK: - Fixtures

    /// Expired items on top of the sample's one: yesterday, a month and a half ago (two of them), so the rows show the
    /// singular, the plural and a stock count.
    private static func addExpiredFood(to server: EverShelfFixtureServer) {
        let calendar = InventoryCalendar.current
        func day(_ offset: Int) -> String {
            calendar.isoString(calendar.calendar.date(byAdding: .day, value: offset, to: calendar.today) ?? calendar.today)
        }
        server.rows += [
            .init(id: 101, name: "Greek Yogurt", quantity: 1, location: .fridge, expiryDate: day(-1), productId: 61),
            .init(id: 102, name: "Cereal", quantity: 2, location: .pantry, expiryDate: day(-45), productId: 62),
        ]
    }

    /// `expired_list` from the rows already past their date, as EverShelf's sensor reports it.
    private static func expiredFoodSensor(_ rows: [EverShelfFixtureServer.Row]) -> EntityState {
        let calendar = InventoryCalendar.current
        let expired = rows.filter { row in
            row.expiryDate.flatMap(calendar.date(fromISO:)).map { calendar.days(until: $0) < 0 } ?? false
        }
        let list: [JSONValue] = expired.map { row in
            .object([
                "name": .string(row.name), "expiry_date": .string(row.expiryDate ?? ""), "location": .string(row.location.rawValue),
                "inventory_id": .number(Double(row.id)), "quantity": .number(row.quantity),
            ])
        }
        return EntityState(entityId: ProfileSummary.expiredFoodEntityId, state: String(expired.count), attributes: ["expired_list": .array(list)])
    }

    private static func people() -> [EntityState] {
        [
            EntityState(entityId: "person.stephen", state: "home", attributes: ["friendly_name": .string("Stephen Fenton")]),
            EntityState(entityId: "person.steph", state: "not_home", attributes: ["friendly_name": .string("Steph Fenton")]),
            EntityState(entityId: "person.guest", state: "home", attributes: ["friendly_name": .string("Guest")]),
        ]
    }
}
#endif
