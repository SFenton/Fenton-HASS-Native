import HassCore
import HassDesign
import SwiftUI

/// Everyone Home Assistant tracks as a person, those at home first, each with a monogram in their colour: the household's
/// two residents take their chore colours (Stephen's blue, Steph's magenta; ``ColorFamily/choreStephen``), a guest the
/// neutral one.
struct ProfilePeopleSection: View {
    var store: EntityStore
    @State private var ids: [String]

    var body: some View {
        let people = ProfileSummary.people(ids.compactMap { store.entity($0).state })
        if !people.isEmpty {
            Section {
                ForEach(people) { person in
                    PersonRow(person: person)
                }
            } header: {
                SettingsSectionHeader("People at Home")
                    .accessibilityIdentifier("profile.people")
            } footer: {
                // Explicit ink: the plain footer measured 3.3:1 in the Account sheet's audit.
                Text(ProfileSummary.homeSummary(people))
                    .foregroundStyle(HassTokens.Surface.secondaryInSheet)
            }
        }
    }

    /// The person ids are read once when the sheet opens: people rarely come and go, and each row then observes its
    /// own entity, so a change of state redraws only that row.
    init(store: EntityStore) {
        self.store = store
        _ids = State(initialValue: store.allValues.keys.filter { $0.hasPrefix("person.") }.sorted())
    }
}
