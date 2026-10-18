import Foundation
#if os(iOS)
import ActivityKit
#endif

/// The Home activity's static attributes. The Swift type name is the wire `attributes-type`
/// (`HomeActivityAttributes`), and a push-to-start token is per type, so renaming it orphans every token already
/// registered.
public struct HomeActivityAttributes: Codable, Hashable, Sendable {
    /// What a push or the app writes into the attributes for the aggregate Home activity.
    public static let homeTag = "fenton-home"
    /// The `attributes-type` the relay sends.
    public static let wireName = "HomeActivityAttributes"
    /// An activity lasts 8 hours at most (the system ends it, then keeps it on the Lock Screen for up to 4 more).
    public static let maxLifetime: TimeInterval = 8 * 3600

    /// `fenton-home` for the Home activity; an automation's own tag for a generic one. It is also the `tag`
    /// Home Assistant's `mobile_app` keys the update token by.
    public var tag: String
    /// "Home" (generic: the automation's `title`).
    public var title: String
    /// `home` or `generic`.
    public var kind: String

    /// Creates attributes.
    public init(tag: String = HomeActivityAttributes.homeTag, title: String = "Home", kind: String = "home") {
        self.tag = tag
        self.title = title
        self.kind = kind
    }

    /// Attributes decode with defaults so a push that sends only `tag` and `title` starts an activity.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tag = try container.decodeIfPresent(String.self, forKey: .tag) ?? Self.homeTag
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Home"
        kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? "home"
    }

    private enum CodingKeys: String, CodingKey { case tag, title, kind }
}

#if os(iOS)
extension HomeActivityAttributes: ActivityAttributes {
    public typealias ContentState = HomeActivityState
}
#endif
