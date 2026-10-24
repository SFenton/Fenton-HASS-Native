@testable import HassDesign
import SwiftUI
import Testing

struct BindingIsPresentTests {
    @Test func tracksTheOptional() {
        var value: String? = "x"
        let source = Binding(get: { value }, set: { value = $0 })
        let present = source.isPresent()
        #expect(present.wrappedValue)
        value = nil
        #expect(!present.wrappedValue)
    }

    @Test func clearsOnDismissAndIgnoresTrue() {
        var value: Int? = 3
        let present = Binding(get: { value }, set: { value = $0 }).isPresent()
        present.wrappedValue = true
        #expect(value == 3)
        present.wrappedValue = false
        #expect(value == nil)
    }
}
