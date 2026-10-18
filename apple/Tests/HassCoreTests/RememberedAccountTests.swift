import Foundation
@testable import HassCore
import Testing

/// The last username and the person's name, kept for the session-expired sign-in.
struct RememberedAccountTests {
    private func store() throws -> (RememberedAccountStore, UserDefaults) {
        let defaults = try #require(UserDefaults(suiteName: "remembered.tests.\(UUID())"))
        return (RememberedAccountStore(defaults: defaults), defaults)
    }

    @Test func nothingIsRememberedUntilAUsernameIsSaved() throws {
        let (store, defaults) = try store()
        #expect(store.username == nil && store.account == nil)
        defaults.set("Stephen Fenton", forKey: RememberedAccountStore.nameKey)
        #expect(store.account == nil, "a name alone is not an account to welcome back")
        defaults.set("", forKey: RememberedAccountStore.usernameKey)
        #expect(store.username == nil, "an empty username is nothing")
    }

    @Test func rememberingKeepsTheUsernameAndPicksUpTheName() throws {
        let (store, defaults) = try store()
        store.remember(username: "stephen")
        #expect(store.account == RememberedAccount(username: "stephen", name: nil))
        defaults.set("Stephen Fenton", forKey: RememberedAccountStore.nameKey)
        #expect(store.account == RememberedAccount(username: "stephen", name: "Stephen Fenton"))
        defaults.set("", forKey: RememberedAccountStore.nameKey)
        #expect(store.account?.name == nil, "an empty name is no name")
    }

    @Test func forgettingClearsBoth() throws {
        let (store, defaults) = try store()
        store.remember(username: "stephen")
        defaults.set("Stephen Fenton", forKey: RememberedAccountStore.nameKey)
        store.forget()
        #expect(store.account == nil)
        #expect(defaults.string(forKey: RememberedAccountStore.nameKey) == nil)
    }

    @Test func theFirstNameIsTheFirstWordOrTheUsername() {
        #expect(RememberedAccount(username: "sf", name: "Stephen Fenton").firstName == "Stephen")
        #expect(RememberedAccount(username: "sf", name: "  Stephen  ").firstName == "Stephen")
        #expect(RememberedAccount(username: "sf", name: nil).firstName == "sf")
        #expect(RememberedAccount(username: "sf", name: "   ").firstName == "sf")
    }
}
