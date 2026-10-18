import Foundation

/// One button on a job (`controls` on the wire). At most ``HomeActivityState/maxControlsPerJob`` ride along.
public struct ActivityControl: Codable, Hashable, Sendable, Identifiable {
    /// How the button reads.
    public enum Role: String, Codable, Hashable, Sendable {
        case normal
        case destructive

        /// An unknown role reads as ``normal``.
        public init(from decoder: any Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Role(rawValue: raw) ?? .normal
        }
    }

    /// The control's id, which Home Assistant maps to a service (`stop`, `cancel_timer`).
    public var id: String
    /// The label.
    public var title: String
    /// Normal or destructive.
    public var role: Role

    /// Creates a control.
    public init(id: String, title: String, role: Role = .normal) {
        self.id = id
        self.title = title
        self.role = role
    }

    private enum CodingKeys: String, CodingKey { case id, title, role }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        role = try container.decodeIfPresent(Role.self, forKey: .role) ?? .normal
    }
}
