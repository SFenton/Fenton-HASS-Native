@testable import HassDesign
import SwiftUI
import Testing

/// ``ImageCard`` and ``RemoteImage``: title line rules and rendering with and without images.
@MainActor
struct ImageCardTests {
    private func render(_ view: some View, size: DynamicTypeSize = .large) -> CGImage? {
        ImageRenderer(content: view.frame(width: 200, height: 260).dynamicTypeSize(size)).cgImage
    }

    @Test func titleLinesReserveTruncateOrWrap() {
        #expect(ImageCard.titleLines(reserved: 2, accessibilitySize: false) == 2...2)
        #expect(ImageCard.titleLines(reserved: nil, accessibilitySize: false) == 1...3)
        #expect(ImageCard.titleLines(reserved: 2, accessibilitySize: true) == 1...100)
    }

    @Test func rendersWithAndWithoutSubtitleAtEverySize() {
        let url = URL(string: "https://example.com/a.jpg")
        for size in [DynamicTypeSize.large, .accessibility5] {
            #expect(render(ImageCard(title: "Lemon Garlic Chicken", subtitle: "3 of 6 ingredients", imageURL: url) {}, size: size) != nil)
            #expect(render(ImageCard(title: "Soup", imageURL: nil, reservedTitleLines: 2) {}, size: size) != nil)
        }
    }

    @Test func remoteImageDrawsEveryPhase() {
        let url = URL(string: "https://example.com/a.jpg")
        let image = RemoteImage(url: url, fallbackURL: URL(string: "https://example.com/b.jpg"))
        #expect(render(image) != nil)
        #expect(render(RemoteImage(url: nil, fallbackURL: url)) != nil)
        #expect(render(RemoteImage(url: url, fallbackURL: url)) != nil)
    }
}
