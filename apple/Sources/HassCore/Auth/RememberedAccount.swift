import Foundation

/// Who last signed in on this phone: the account name and the person's name, kept so a rejected session can say
/// "Welcome back, Stephen" and ask for the password alone (`.agents/platforms/apple/auth.md`, "Session expired").
///
/// Never the password, and nothing secret: the username is what the person types in the first field, and the name is the
/// display name the profile button already shows.
public struct RememberedAccount: Equatable, Sendable {
    /// The Home Assistant username, as signed in with.
    public var username: String
    /// The person's display name, when the app has read it.
    public var name: String?

    /// Creates an account.
    public init(username: String, name: String? = nil) {
        self.username = username
        self.name = name
    }

    /// The first word of the name ("Stephen" from "Stephen Fenton"), or the username when there is no name.
    public var firstName: String {
        let first = name?.split(whereSeparator: \.isWhitespace).first.map(String.init)
        return first ?? username
    }
}

/// Reads and writes the remembered account in `UserDefaults` (not the Keychain: neither value is a secret).
public struct RememberedAccountStore: @unchecked Sendable {
    /// The key for the last username.
    public static let usernameKey = "signin.lastUsername"
    /// The key for the person's display name. The profile button keeps its name here too (`ShellNavigator.profileName`), so
    /// the name is current without a second write.
    public static let nameKey = "shell.profileName"

    private let defaults: UserDefaults

    /// Creates a store over `defaults`.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The last username typed on a successful sign-in, if any.
    public var username: String? {
        let value = defaults.string(forKey: Self.usernameKey)
        return value?.isEmpty == false ? value : nil
    }

    /// The remembered account: nil until a username is known.
    public var account: RememberedAccount? {
        guard let username else { return nil }
        let name = defaults.string(forKey: Self.nameKey)
        return RememberedAccount(username: username, name: name?.isEmpty == false ? name : nil)
    }

    /// Remembers the username after a successful sign-in.
    public func remember(username: String) {
        defaults.set(username, forKey: Self.usernameKey)
    }

    /// Forgets the username (Use a Different Account) and the name that went with it.
    public func forget() {
        defaults.removeObject(forKey: Self.usernameKey)
        defaults.removeObject(forKey: Self.nameKey)
    }
}
