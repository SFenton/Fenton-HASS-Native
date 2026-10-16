import SwiftUI
@testable import HassUI
import Testing

@MainActor
struct SystemAccessibilityGalleryTests {
    @Test func pageRendersAndIsReachableByName() {
        #expect(ComponentGallery.Page(rawValue: "system-accessibility") == .systemAccessibility)
        let renderer = ImageRenderer(content: ComponentGallery(page: .systemAccessibility).frame(width: 402, height: 874))
        #expect(renderer.cgImage != nil)
    }
}
