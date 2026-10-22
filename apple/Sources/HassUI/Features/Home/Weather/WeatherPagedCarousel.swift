import HassDesign
import SwiftUI

/// A horizontally paging row of equal-width cells with a page indicator and, on wide layouts, previous and next
/// buttons (web `useHorizontalScrollControls`, `WeatherScrollControls`, `WeatherCarouselPagination`).
///
/// Each page holds ``WeatherCarouselPaging/perPage`` whole cells; scrolling snaps to pages in a UIKit paging scroll view
/// (`PagedRow`), which moves without touching the sheet's view graph (and has no `scrollTargetBehavior`, which leaks
/// observation state on every resume, `.agents/patterns/resume-lifecycle.md`). VoiceOver reads the hours on the page on
/// screen (the scroll view exposes only those, and announces "Page 2 of 3" when it changes) and pages with a three-finger
/// swipe, the adjustable page indicator or, on wide layouts (regular horizontal size class), 44 pt previous and next
/// buttons, because the web shows them for pointer devices. HIG: Scroll views, Page controls.
struct WeatherPagedCarousel<Cell: View>: View {
    var count: Int
    /// Hours per page in a compact and a regular layout at the default text size.
    var compactPerPage: Int
    var regularPerPage: Int
    /// Spoken name of the row, e.g. `24-hour weather forecast`.
    var label: String
    /// Identifier prefix: the row is `<identifier>.carousel`, its indicator `<identifier>.pages`.
    var identifier: String
    var cell: (_ index: Int) -> Cell

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The first hour on screen; the page is derived from it.
    @State private var firstVisible: Int? = 0

    /// Space reserved at each end for the previous and next buttons.
    private let controlInset = HassTokens.minTarget + HassTokens.Spacing.s

    private var paging: WeatherCarouselPaging {
        WeatherCarouselPaging(
            count: count,
            perPage: WeatherCarouselPaging.hoursPerPage(compact: compactPerPage, regular: regularPerPage, sizeClass: sizeClass, typeSize: typeSize)
        )
    }

    private var showsControls: Bool { sizeClass == .regular && paging.overflows }

    var body: some View {
        let paging = paging
        VStack(spacing: HassTokens.Spacing.xs) {
            strip(paging: paging)
                .padding(.horizontal, showsControls ? controlInset : 0)
                .overlay { if showsControls { controls(paging: paging) } }
            if paging.overflows { indicator(paging: paging) }
        }
    }

    private func strip(paging: WeatherCarouselPaging) -> some View {
        // The paging happens in UIKit (`PagedRow`): a swipe on a SwiftUI `ScrollView` nested in the sheet's own scroll view
        // committed its offset through the sheet's view graph on every frame.
        return PagedRow(itemCount: count, perPage: paging.perPage, firstVisible: $firstVisible, animatesPaging: !reduceMotion) { index in
            // VoiceOver reads the page on screen (the hosted scroll view exposes only that page) and pages with Previous
            // and Next, the indicator or a three-finger swipe.
            cell(index)
        }
        .accessibilityIdentifier("\(identifier).carousel")
    }

    private func indicator(paging: WeatherCarouselPaging) -> some View {
        let current = paging.page(containing: firstVisible)
        return HStack(spacing: HassTokens.Spacing.xs + 2) {
            ForEach(0..<paging.pageCount, id: \.self) { index in
                Capsule()
                    .fill(index == current ? HassTokens.Ink.onDark : HassTokens.Ink.onDark.opacity(0.45))
                    .quickTransition("WeatherPagedCarousel", value: index == current)
                    .frame(width: index == current ? 18 : 7, height: 7)
            }
        }
        // The dots stay small; the element is a full 44 pt target for Switch Control and the audit's hit-area check.
        .frame(maxWidth: .infinity, minHeight: HassTokens.minTarget)
        .contentShape(Rectangle())
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
        let current = paging.page(containing: firstVisible)
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
        .quickTransition("WeatherPagedCarousel", value: disabled)
        .accessibilityLabel(label)
        .accessibilityIdentifier("\(identifier).\(id)")
    }

    private func go(to target: Int, paging: WeatherCarouselPaging) {
        // The row scrolls across to the page itself (or jumps with Reduce Motion).
        firstVisible = paging.firstIndex(ofPage: paging.clamped(target))
    }
}
