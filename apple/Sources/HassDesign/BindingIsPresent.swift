import SwiftUI

public extension Binding {
    /// A `Bool` binding that is true while the optional is non-nil and clears it when set to false.
    ///
    /// The one place a presenter's `isPresented:` is derived from an optional, so views do not hand-build
    /// `Binding(get:set:)` in their bodies. Prefer `sheet(item:)` and `alert(item:)` where the item itself is shown.
    func isPresent<Wrapped>() -> Binding<Bool> where Value == Wrapped? {
        Binding<Bool>(
            get: { wrappedValue != nil },
            set: { if !$0 { wrappedValue = nil } }
        )
    }
}
