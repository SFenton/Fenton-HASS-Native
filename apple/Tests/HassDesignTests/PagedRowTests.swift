@testable import HassDesign
import SwiftUI
import Testing

/// ``PagedRow`` lays its cells in a row whatever the platform's scroll view; the paging itself is UIKit's and is covered
/// by the Weather journeys.
@MainActor
struct PagedRowTests {
    private func render(count: Int, perPage: Int, clips: Bool = true) -> CGImage? {
        var first: Int? = 0
        let binding = Binding(get: { first }, set: { first = $0 })
        let row = PagedRow(itemCount: count, perPage: perPage, firstVisible: binding, animatesPaging: false, clipsToBounds: clips) { index in
            Text("Cell \(index)")
        }
        return ImageRenderer(content: row.frame(width: 300, height: 60)).cgImage
    }

    @Test func rendersARowOfPages() {
        #expect(render(count: 24, perPage: 5) != nil)
        #expect(render(count: 24, perPage: 5, clips: false) != nil)
    }

    @Test func aShortOrEmptyRowStillRenders() {
        #expect(render(count: 3, perPage: 5) != nil)
        #expect(render(count: 0, perPage: 5) != nil)
        #expect(render(count: 4, perPage: 0) != nil)
    }
}
