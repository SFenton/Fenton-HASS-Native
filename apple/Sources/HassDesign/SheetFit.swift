import SwiftUI

// MARK: - Height policy

/// How tall a ``SwiftUI/View/hassSheet(_:height:appearance:fitKey:)`` modal opens on iPhone.
///
/// Owner decision, 2026-10-16 (replacing 2026-10-13's "all modals full height"): a sheet opens only as tall as its
/// content needs, so a short prompt does not leave a screen of empty ground. HIG Sheets: "Use the smallest detent
/// that shows the content; let people expand when the content is long" and "Prefer medium or custom detents for
/// short content".
public enum HassSheetHeight: Sendable, Equatable {
    /// As tall as the content (``SheetFit``), capped at the large detent; longer content scrolls. The default.
    case fitted
    /// Always the large detent. Remotes, any modal with a section tab bar, sheets that navigate between pages and
    /// sheets over live video: their height must not change with a tab or a pushed page.
    case full
}

/// The pure sizing decisions behind ``HassSheetHeight/fitted``: measured content to a presentation detent.
public enum SheetFit {
    /// A detent the system understands, kept as plain data so the choice can be tested without a presentation.
    public enum Detent: Equatable, Sendable {
        /// A custom height in points (`PresentationDetent.height`).
        case height(CGFloat)
        /// The large detent: the content is as tall as the sheet can be, or taller.
        case large
        /// Shown until the first measurement arrives, so the sheet never opens full and then shrinks.
        case provisional
    }

    /// The shortest fitted sheet: grabber, header and one row. A shorter reading is a measurement taken before the
    /// content laid out.
    public static let minimumHeight: CGFloat = 220

    /// A content height within this many points of the available height opens at `.large` instead, so a custom
    /// detent a hair under large does not leave a sliver of the page above it.
    public static let largeSnap: CGFloat = 24

    /// A reading smaller than this change is noise: the sheet does not move for it.
    public static let hysteresis: CGFloat = 2

    /// The detent for measured content.
    ///
    /// - Parameters:
    ///   - contentHeight: The sheet's wanted height (content plus the header and bottom insets), or nil before the
    ///     first measurement.
    ///   - availableHeight: The height of the large detent.
    /// - Returns: ``Detent/provisional`` before a measurement; ``Detent/large`` when the content reaches the large
    ///   detent; otherwise a ``Detent/height(_:)`` of at least ``minimumHeight``.
    public static func detent(contentHeight: CGFloat?, availableHeight: CGFloat) -> Detent {
        guard let contentHeight, contentHeight.isFinite else { return .provisional }
        guard availableHeight.isFinite, availableHeight > 0 else { return .large }
        if contentHeight >= availableHeight - largeSnap { return .large }
        return .height(max(contentHeight.rounded(.up), minimumHeight))
    }

    /// Whether a new reading moves the sheet.
    public static func shouldUpdate(from old: CGFloat?, to new: CGFloat) -> Bool {
        guard new.isFinite, new > 0 else { return false }
        guard let old else { return true }
        return abs(new - old) >= hysteresis
    }

    /// Whether a scroll view's reading is the page's own vertical scroller rather than a chip rail or carousel
    /// inside it: a horizontal scroller's content is wider than its container, and a tiny container is a rail.
    public static func isPageScroller(contentWidth: CGFloat, containerWidth: CGFloat, containerHeight: CGFloat) -> Bool {
        contentWidth <= containerWidth + 1 && containerHeight >= 120
    }

    /// The wanted sheet height from a scroll view's geometry: its content plus the insets the header and the home
    /// indicator (and a pinned tab bar) add around it.
    public static func wantedHeight(contentHeight: CGFloat, topInset: CGFloat, bottomInset: CGFloat) -> CGFloat {
        max(0, contentHeight) + max(0, topInset) + max(0, bottomInset)
    }

    /// The wanted sheet height from the sheet's own height and the scroller's viewport: whatever the sheet holds
    /// besides the scroller (header, grabber, a pinned tab bar, safe areas) plus the scroller's content. Unlike the
    /// insets, this counts a scroller laid out *below* the header (iPad's form sheet) as well as one under it.
    public static func wantedHeight(sheetHeight: CGFloat, viewportHeight: CGFloat, contentHeight: CGFloat) -> CGFloat {
        max(0, sheetHeight - viewportHeight) + max(0, contentHeight)
    }

    /// One reading of the page's vertical scroller.
    public struct Reading: Equatable, Sendable {
        /// The scroller's content height.
        public var content: CGFloat
        /// The scroller's viewport height.
        public var viewport: CGFloat
        /// The insets the scroller reports above and below its content.
        public var topInset: CGFloat
        public var bottomInset: CGFloat

        public init(content: CGFloat, viewport: CGFloat = 0, topInset: CGFloat = 0, bottomInset: CGFloat = 0) {
            self.content = content
            self.viewport = viewport
            self.topInset = topInset
            self.bottomInset = bottomInset
        }
    }
}

// MARK: - Measurement channel

/// Receives the measured height of a fitted sheet's content, from the page ``SwiftUI/View/modalChrome()`` is
/// applied to. Created by `hassSheet` and handed down through the environment.
@MainActor
@Observable
public final class SheetFitModel {
    /// The wanted height of the sheet, nil until the page has reported.
    public private(set) var contentHeight: CGFloat?

    /// Whoever reported first: the sheet's root page. Pages pushed inside the sheet report too and are ignored, so
    /// the sheet keeps its height across a push and a pop instead of resizing under the reader.
    private var owner: UUID?
    private var reading: SheetFit.Reading?
    private var sheetHeight: CGFloat?
    private var safeTop: CGFloat = 0
    private var safeBottom: CGFloat = 0
    private let onChange: (CGFloat) -> Void

    /// Creates the model.
    /// - Parameters:
    ///   - initial: A height remembered from the last time this sheet opened, so it opens at the right height.
    ///   - onChange: Called with each accepted height.
    public init(initial: CGFloat? = nil, onChange: @escaping (CGFloat) -> Void = { _ in }) {
        contentHeight = initial
        self.onChange = onChange
    }

    /// Records a reading from a page.
    /// - Parameters:
    ///   - height: The content height, with no insets.
    ///   - page: The reporting page's identity.
    public func report(_ height: CGFloat, from page: UUID) {
        report(SheetFit.Reading(content: height), from: page)
    }

    /// Records a reading from a page.
    public func report(_ reading: SheetFit.Reading, from page: UUID) {
        if owner == nil { owner = page }
        guard owner == page else { return }
        self.reading = reading
        recompute()
    }

    /// Records the presented sheet's own height (full, safe areas included).
    public func setSheetHeight(_ height: CGFloat) {
        sheetHeight = height
        recompute()
    }

    /// Records the page's safe-area insets: the navigation bar above it and the home indicator and a pinned tab bar
    /// below it. A scroller laid out below the header (iPad's form sheet) reports no inset for the bar.
    public func setSafeInsets(top: CGFloat, bottom: CGFloat) {
        safeTop = top
        safeBottom = bottom
        recompute()
    }

    /// Whether the sheet-minus-scroller estimate counts (regular width, where the scroller sits below the header).
    /// Set by the presenting sheet from its size class.
    public var usesSheetEstimate = false

    /// The content plus the larger of the scroller's insets and the page's safe areas; at regular width also the larger of
    /// that and the sheet's height minus the scroller's viewport plus its content, so the sheet is never too short.
    private func recompute() {
        guard let reading else { return }
        var wanted = SheetFit.wantedHeight(contentHeight: reading.content, topInset: max(reading.topInset, safeTop),
                                           bottomInset: max(reading.bottomInset, safeBottom)).rounded()
        // The sheet-minus-scroller estimate is for a scroller laid out below the header (iPad's form sheet). On a phone
        // the scroller runs under the header and the safe areas above are the chrome, and counting the sheet's own height
        // there made a ratchet: a scroller that does not grow with the sheet reads the same viewport at every height, so
        // each taller sheet asked for 14 pt more until it reached large (the bathroom fan sheet, 2026-10-17: 400 pt of
        // blank ground under a 330 pt page).
        if usesSheetEstimate, let sheetHeight, reading.viewport > 0 {
            wanted = max(wanted, SheetFit.wantedHeight(sheetHeight: sheetHeight, viewportHeight: reading.viewport,
                                                       contentHeight: reading.content).rounded())
        }
        guard SheetFit.shouldUpdate(from: contentHeight, to: wanted) else { return }
        contentHeight = wanted
        onChange(wanted)
    }
}

extension EnvironmentValues {
    /// Where a fitted sheet's pages report their height; nil in a full-height sheet and outside sheets.
    @Entry var sheetFit: SheetFitModel?
}

/// Heights remembered per call site for the life of the process, so the second time a sheet opens it opens at its
/// final height at once. Keys are the `#fileID:#line` of the `hassSheet` call.
@MainActor
enum SheetFitMemory {
    private static var heights: [String: CGFloat] = [:]

    static func height(for key: String) -> CGFloat? { heights[key] }
    static func remember(_ height: CGFloat, for key: String) { heights[key] = height }
    /// Forgets everything (tests).
    static func reset() { heights.removeAll() }
}

// MARK: - Reporting

extension View {
    /// Reports this page's scroll content height to the enclosing fitted sheet (iOS 18 and later; earlier systems
    /// keep the provisional detent and the system's own scrolling).
    func reportsSheetFit() -> some View {
        modifier(SheetFitReporter())
    }
}

private struct SheetFitReporter: ViewModifier {
    @Environment(\.sheetFit) private var fit
    @State private var page = UUID()

    func body(content: Content) -> some View {
        if #available(iOS 18.0, macOS 15.0, watchOS 11.0, *), let fit {
            content
                .onScrollGeometryChange(for: SheetFit.Reading?.self) { geometry in
                    guard SheetFit.isPageScroller(contentWidth: geometry.contentSize.width,
                                                  containerWidth: geometry.containerSize.width,
                                                  containerHeight: geometry.containerSize.height) else { return nil }
                    return SheetFit.Reading(
                        content: geometry.contentSize.height.rounded(), viewport: geometry.containerSize.height.rounded(),
                        topInset: geometry.contentInsets.top.rounded(), bottomInset: geometry.contentInsets.bottom.rounded())
                } action: { _, reading in
                    if let reading { fit.report(reading, from: page) }
                }
                .background {
                    Color.clear
                        .onGeometryChange(for: [CGFloat].self) {
                            [$0.safeAreaInsets.top.rounded(), $0.safeAreaInsets.bottom.rounded()]
                        } action: { insets in
                            fit.setSafeInsets(top: insets[0], bottom: insets[1])
                        }
                        .accessibilityHidden(true)
                }
        } else {
            content
        }
    }
}

// MARK: - Detent resolution

/// The height of the large detent on this device: the key window below its top safe area. 0 where there is no window
/// (macOS, `swift test`), which resolves every fitted sheet to `.large`.
@MainActor
enum LargeDetent {
    static func height() -> CGFloat {
        #if os(iOS)
        let windows = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.windows }.flatMap { $0 }
        guard let window = windows.first(where: \.isKeyWindow) ?? windows.first else { return 0 }
        return window.bounds.height - window.safeAreaInsets.top - 10
        #else
        return 0
        #endif
    }
}

/// Applies a sheet's detents: the large detent for ``HassSheetHeight/full``, a measured custom height for
/// ``HassSheetHeight/fitted``.
struct SheetHeightModifier: ViewModifier {
    var height: HassSheetHeight
    var fitKey: String

    @ViewBuilder
    func body(content: Content) -> some View {
        switch height {
        case .full:
            content.presentationDetents([.large])
        case .fitted:
            FittedSheet(content: content, fitKey: fitKey)
        }
    }
}

/// A fitted sheet: owns the measurement model, publishes it to the pages below and sets the detent from it.
private struct FittedSheet<Content: View>: View {
    var content: Content
    var fitKey: String
    @State private var model: SheetFitModel
    @State private var available: CGFloat
    @Environment(\.horizontalSizeClass) private var sizeClass

    init(content: Content, fitKey: String) {
        self.content = content
        self.fitKey = fitKey
        let key = fitKey
        _model = State(initialValue: SheetFitModel(initial: SheetFitMemory.height(for: key)) { height in
            SheetFitMemory.remember(height, for: key)
        })
        _available = State(initialValue: LargeDetent.height())
    }

    var body: some View {
        content
            .environment(\.sheetFit, model)
            .onChange(of: sizeClass, initial: true) { model.usesSheetEstimate = sizeClass == .regular }
            .presentationDetents(Self.detents(for: SheetFit.detent(contentHeight: model.contentHeight, availableHeight: available)))
            .background { LargeDetentProbe(height: $available) }
            .background {
                // The presented view's full height, safe areas included.
                Color.clear
                    .ignoresSafeArea()
                    .onGeometryChange(for: CGFloat.self) { $0.size.height.rounded() } action: { model.setSheetHeight($0) }
                    .accessibilityHidden(true)
            }
    }

    static func detents(for detent: SheetFit.Detent) -> Set<PresentationDetent> {
        switch detent {
        case .large: [.large]
        case .provisional: [.medium]
        case let .height(value): [.height(value)]
        }
    }
}

/// Reads the large detent's height again when the sheet's size changes (a rotation, a fold).
private struct LargeDetentProbe: View {
    @Binding var height: CGFloat

    var body: some View {
        Color.clear
            .onGeometryChange(for: CGSize.self) { $0.size } action: { _ in
                let value = LargeDetent.height()
                if abs(value - height) > 0.5 { height = value }
            }
            .accessibilityHidden(true)
    }
}
