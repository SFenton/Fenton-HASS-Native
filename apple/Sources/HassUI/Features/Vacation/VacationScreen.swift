import HassCore
import HassDesign
import SwiftUI

/// Settings → Vacation, wired to the live connection.
struct VacationRoute: View {
    @Environment(HassConnection.self) private var connection

    var body: some View {
        VacationScreen(store: connection.store, responder: connection, caller: connection) {
            try? await connection.currentUser().id
        }
    }
}

/// The Vacation entry (web route `vacation`): a chooser between Vacation Mode and Solo Trip, or straight to
/// the engaged one (web `vacationFeaturePath`).
struct VacationScreen: View {
    @State private var household: HouseholdAwayController
    @State private var viewer: HouseholdResident?
    /// The engaged page this screen last showed. Turning that mode off keeps its page (the web stays on
    /// `vacation-mode` / `solo-trip`) instead of swapping the root back to the chooser under the person.
    @State private var lastEngaged: Vacation.Route?
    private let store: EntityStore
    private let caller: any HassServiceCalling
    private let currentUserId: @MainActor () async -> String?

    /// Creates the screen.
    /// - Parameters:
    ///   - store: Live state.
    ///   - responder: Household Away commands.
    ///   - caller: Vacation helper service calls.
    ///   - currentUserId: The signed-in Home Assistant user, for "You".
    init(store: EntityStore, responder: any HassServiceResponding, caller: any HassServiceCalling,
         currentUserId: @escaping @MainActor () async -> String? = { nil }) {
        self.store = store
        self.caller = caller
        self.currentUserId = currentUserId
        _household = State(initialValue: HouseholdAwayController(store: store, responder: responder))
    }

    var body: some View {
        content
            .task { viewer = HouseholdResident.forHaUserId(await currentUserId()) }
            .onChange(of: route, initial: true) { _, route in
                if route != .chooser { lastEngaged = route }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch displayedRoute {
        case .chooser:
            VacationChooser(household: household, store: store, caller: caller, viewer: viewer)
        case .vacationMode:
            VacationModeScreen(store: store, household: household, caller: caller)
        case .soloTrip:
            SoloTripScreen(household: household, viewer: viewer)
        }
    }

    /// The live route, or the engaged page already shown once its mode turns off.
    private var displayedRoute: Vacation.Route {
        route == .chooser ? lastEngaged ?? .chooser : route
    }

    private var route: Vacation.Route {
        Vacation.route(
            snapshot: household.snapshot,
            vacationModeOn: store.entity(Vacation.modeEntityId).state?.state == "on",
            invalidDatesPending: store.entity(Vacation.invalidDatesPendingEntityId).state?.state == "on"
        )
    }
}

/// A page the chooser pushes.
enum VacationPage: Hashable, Sendable {
    case vacationMode, soloTrip
}

/// The two away modes as settings rows (web `VacationChooserPage`).
struct VacationChooser: View {
    var household: HouseholdAwayController
    var store: EntityStore
    var caller: any HassServiceCalling
    var viewer: HouseholdResident?

    var body: some View {
        List {
            Section {
                NavigationLink(value: VacationPage.vacationMode) {
                    SettingsLinkRow(title: Vacation.Copy.vacationLinkTitle, subtitle: Vacation.Copy.vacationLinkSubtitle,
                                    symbol: SymbolMap.symbol(for: "mdi:airplane"), showsChevron: false)
                }
                .accessibilityIdentifier("vacation.chooser.vacationMode")
                NavigationLink(value: VacationPage.soloTrip) {
                    SettingsLinkRow(title: SoloTripCopy.title, subtitle: soloTripSubtitle,
                                    symbol: SymbolMap.symbol(for: "mdi:bag-suitcase"), showsChevron: false)
                }
                .accessibilityIdentifier("vacation.chooser.soloTrip")
            }
        }
        .navigationTitle(Vacation.Copy.chooserTitle)
        // Values and a registered destination, like the rest of the Settings stack (HIG Navigation: one destination style).
        .pageDestination(for: VacationPage.self) { page in
            switch page {
            case .vacationMode: VacationModeScreen(store: store, household: household, caller: caller)
            case .soloTrip: SoloTripScreen(household: household, viewer: viewer)
            }
        }
    }

    private var soloTripSubtitle: String {
        household.setupUnavailable ? SoloTripCopy.setupRequiredSubtitle : SoloTripCopy.chooserSubtitle
    }
}
