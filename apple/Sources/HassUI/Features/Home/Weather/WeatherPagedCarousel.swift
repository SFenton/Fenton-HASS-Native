import HassDesign
import SwiftUI

/// A horizontally paging row of equal-width cells with a page indicator and, on wide layouts, previous and next
/// buttons (web `useHorizontalScrollControls`, `WeatherScrollControls`, `WeatherCarouselPagination`).
///
/// Each page holds as many whole cells as fit; scrolling snaps to pages (`scrollTargetBehavior(.paging)`). Every cell
/// stays in the accessibility tree, so VoiceOver reaches each hour and scrolls the row itself; the page indicator is
/// an adjustable element. Wide layouts (regular horizontal size class) add 44 pt previous and next buttons, because
/// the web shows them for pointer devices. HIG: Scroll views, Page controls.
struct WeatherPagedCarousel<Cell: View>: View {
    var count: Int
    /// Narrowest a cell may be at the current text size.
    var minItemWidth: CGFloat
    var spacing: CGFloat = HassTokens.Spacing.s
    /// Spoken name of the row, e.g. `24-hour weather forecast`.
    var label: String
    /// Identifier prefix: the row is `<identifier>.carousel`, its indicator `<identifier>.pages`.
    var identifier: String
    var cell: (_ index: Int, _ width: CGFloat) -> Cell

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var viewportWidth: CGFloat = 0
    @State private var page: Int? = 0

    /// Space reserved at each end for the previous and next buttons.
    private let controlInset = HassTokens.minTarget + HassTokens.Spacing.s

    private var showsControls: Bool { sizeClass == .regular && paging.overflows }

    private var paging: WeatherCarouselPaging {
        WeatherCarouselPaging(count: count, viewportWidth: viewportWidth, minItemWidth: minItemWidth, spacing: spacing)
    }

    var body: some View {
        let paging = paging
        let width = paging.itemWidth(viewportWidth: viewportWidth)
        VStack(spacing: HassTokens.Spacing.xs) {
            strip(paging: paging, itemWidth: width)
                .padding(.horizontal, showsControls ? controlInset : 0)
                .overlay { if showsControls { controls(paging: paging) } }
            if paging.overflows { indicator(paging: paging) }
        }
        .onChange(of: paging.pageCount) { _, pages in
            if let page, page >= pages { self.page = pages - 1 }
        }
    }

    private func strip(paging: WeatherCarouselPaging, itemWidth: CGFloat) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(0..<paging.pageCount, id: \.self) { pageIndex in
                    HStack(alignment: .top, spacing: paging.spacing) {
                        ForEach(paging.indices(onPage: pageIndex), id: \.self) { index in
                            cell(index, itemWidth).frame(width: itemWidth)
                        }
                    }
                    .containerRelativeFrame(.horizontal, alignment: .leading)
                    .id(pageIndex)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $page)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: CarouselWidthKey.self, value: proxy.size.width)
            }
        }
        .onPreferenceChange(CarouselWidthKey.self) { viewportWidth = $0 }
        .accessibilityIdentifier("\(identifier).carousel")
    }

    private func indicator(paging: WeatherCarouselPaging) -> some View {
        let current = paging.clamped(page)
        return HStack(spacing: HassTokens.Spacing.xs + 2) {
            ForEach(0..<paging.pageCount, id: \.self) { index in
                Capsule()
                    .fill(index == current ? HassTokens.Ink.onDark : HassTokens.Ink.onDark.opacity(0.45))
                    .frame(width: index == current ? 18 : 7, height: 7)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) pages")
        .accessibilityValue(paging.pageDescription(current))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: go(to: current + 1, paging: paging)
            case .decrement: go(to: current - 1, paging: paging)
            @unknown default: break
            }
        }
        .accessibilityIdentifier("\(identifier).pages")
    }

    private func controls(paging: WeatherCarouselPaging) -> some View {
        let current = paging.clamped(page)
        return HStack {
            controlButton(symbol: WeatherSymbols.previous, label: "Previous \(label)", id: "previous", disabled: current == 0) {
                go(to: current - 1, paging: paging)
            }
            Spacer(minLength: 0)
            controlButton(symbol: WeatherSymbols.next, label: "Next \(label)", id: "next", disabled: current >= paging.pageCount - 1) {
                go(to: current + 1, paging: paging)
            }
        }
    }

    private func controlButton(symbol: String, label: String, id: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(HassTokens.Ink.onDark)
                .frame(width: HassTokens.minTarget, height: HassTokens.minTarget)
                .background(Color.black.opacity(0.35), in: Circle())
                .overlay(Circle().strokeBorder(HassTokens.Ink.onDark.opacity(0.25)))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
        .accessibilityLabel(label)
        .accessibilityIdentifier("\(identifier).\(id)")
    }

    private func go(to target: Int, paging: WeatherCarouselPaging) {
        let next = paging.clamped(target)
        if reduceMotion { page = next } else { withAnimation(.smooth) { page = next } }
    }
}

private struct CarouselWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
