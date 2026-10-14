import Foundation
import HassCore
import Observation

/// A page to open, stamped so the same destination twice in a row still opens.
public struct PushNavigationRequest: Equatable, Sendable {
    /// Increases with each request.
    public var id: Int
    /// The page.
    public var destination: PushDestination
}
