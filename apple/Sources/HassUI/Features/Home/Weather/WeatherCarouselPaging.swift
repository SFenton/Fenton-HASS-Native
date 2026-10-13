import CoreGraphics

/// Page math for the hourly carousels: how many hours fit, how wide each is, and which hours open each page.
///
/// The web measures the DOM (`useHorizontalScrollControls`); native derives the same pages from the measured width so
/// they can be unit tested. Each page holds as many whole hours as fit, so the scroll always snaps to a page and no
/// hour is ever cut in half.
struct WeatherCarouselPaging: Equatable {
    /// Hours shown before the width is measured.
    static let defaultPerPage = 6

    var count: Int
    var perPage: Int
    var spacing: CGFloat

    /// Pages for `count` items in a viewport. A viewport of 0 (not measured yet) uses ``defaultPerPage``.
    init(count: Int, viewportWidth: CGFloat, minItemWidth: CGFloat, spacing: CGFloat) {
        self.count = max(0, count)
        self.spacing = spacing
        if viewportWidth <= 0 || minItemWidth <= 0 {
            perPage = Self.defaultPerPage
        } else {
            perPage = max(1, Int(((viewportWidth + spacing) / (minItemWidth + spacing)).rounded(.down)))
        }
    }

    var pageCount: Int { count == 0 ? 1 : Int((Double(count) / Double(perPage)).rounded(.up)) }

    /// Whether more than one page exists, i.e. the carousel scrolls.
    var overflows: Bool { pageCount > 1 }

    /// The width of one item so `perPage` items and their gaps fill the viewport exactly.
    func itemWidth(viewportWidth: CGFloat) -> CGFloat {
        guard viewportWidth > 0 else { return 44 }
        return max(1, (viewportWidth - spacing * CGFloat(perPage - 1)) / CGFloat(perPage))
    }

    /// The item indices on a page.
    func indices(onPage page: Int) -> Range<Int> {
        let start = min(count, max(0, page) * perPage)
        return start..<min(count, start + perPage)
    }

    /// The page showing an item.
    func page(containing index: Int) -> Int { max(0, min(pageCount - 1, index / perPage)) }

    /// The page index clamped to the available pages.
    func clamped(_ page: Int?) -> Int { max(0, min(pageCount - 1, page ?? 0)) }

    /// `Page 2 of 4`, for the pagination element's value.
    func pageDescription(_ page: Int) -> String { "Page \(clamped(page) + 1) of \(pageCount)" }
}
