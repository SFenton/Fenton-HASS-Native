import HassDesign
import SwiftUI

// MARK: - On-demand split stack

/// A section stack whose root page can open an item beside itself (`.agents/design/apple/split-view.md`,
/// ported from FestivalNativeApps `OnDemandSplitStack`).
///
/// - Where ``SplitPolicy/geometry(container:isRegularWidth:hinge:)`` allows a split (iPad landscape,
///   unfolded iPhone Duo landscape), opening an item springs the root page to the leading pane and shows
///   the item in a trailing `NavigationStack` with a **Close** button. Pages that always split
///   (`alwaysSplit`, Settings) keep the trailing pane open with a placeholder while nothing is selected.
/// - Everywhere else (iPhone, Duo folded and unfolded portrait, iPad portrait) the same item is pushed on
///   the leading stack with the system Back button: single page, never split.
/// - A fold, unfold or rotation moves the open item between the trailing pane and the push, one
///   run-loop turn after the window update and unanimated (Festival #346).
struct OnDemandSplitStack<Item: Hashable, Root: View, Detail: View, Placeholder: View>: View {
    /// The leading stack's path.
    @Binding var path: NavigationPath
    /// The open item, if any. Rows set it; Close, Back and Escape clear it.
    @Binding var openItem: Item?
    /// Keep the trailing pane open with ``placeholder`` while nothing is selected.
    var alwaysSplit: Bool
    var root: () -> Root
    var detail: (Item) -> Detail
    var placeholder: () -> Placeholder

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.windowHinge) private var hinge
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var containerFrame: CGRect = .zero
    /// The geometry in effect; follows the computed one a run-loop turn later on window changes.
    @State private var appliedGeometry: SplitGeometry?

    /// Creates a split stack.
    /// - Parameters:
    ///   - path: The leading stack's path.
    ///   - openItem: The open item.
    ///   - alwaysSplit: Keep the trailing pane open with `placeholder` while nothing is selected.
    ///   - root: The section's root (list) page.
    ///   - detail: The page for an open item.
    ///   - placeholder: The trailing pane's content while nothing is selected (`alwaysSplit` only).
    init(
        path: Binding<NavigationPath>, openItem: Binding<Item?>, alwaysSplit: Bool = false,
        @ViewBuilder root: @escaping () -> Root, @ViewBuilder detail: @escaping (Item) -> Detail,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        _path = path
        _openItem = openItem
        self.alwaysSplit = alwaysSplit
        self.root = root
        self.detail = detail
        self.placeholder = placeholder
    }

    private var computedGeometry: SplitGeometry? {
        SplitPolicy.geometry(container: containerFrame, isRegularWidth: horizontalSizeClass == .regular, hinge: hinge)
    }

    var body: some View {
        let geometry = appliedGeometry
        let showsTrailing = geometry != nil && (openItem != nil || alwaysSplit)
        HStack(spacing: 0) {
            NavigationStack(path: $path) {
                root()
                    .sectionRootChrome()
                    .pageChrome()
                    .navigationDestination(item: pushBinding(isSplit: geometry != nil)) { item in
                        detail(item).pageChrome()
                    }
            }
            .frame(width: showsTrailing ? geometry?.leadingWidth : nil)
            .frame(maxWidth: showsTrailing ? nil : .infinity)
            if showsTrailing, let geometry {
                band(geometry)
                trailingPane
                    .frame(width: geometry.trailingWidth)
                    .transition(reduceMotion ? .opacity : .move(edge: .trailing))
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.35), value: openItem)
        // Measure the space offered, not the HStack: with fixed pane widths the HStack keeps its split
        // width after a rotation to portrait, so the split never turned off (it overflowed the window).
        // `minWidth: 0` too: without it a flexible frame still grows to its child's width.
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { containerFrame = $0 }
        .onChange(of: computedGeometry, initial: true) { _, newGeometry in
            guard newGeometry != appliedGeometry else { return }
            if appliedGeometry == nil || newGeometry == nil {
                // Split turning on or off: apply the new shape one run-loop turn after the window's own
                // update, unanimated (Festival #346: same-update changes blanked the Duo's outer display).
                Task { @MainActor in
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { appliedGeometry = computedGeometry }
                }
            } else {
                appliedGeometry = newGeometry
            }
        }
    }

    /// Pushes the open item on the leading stack only while the window does not split.
    private func pushBinding(isSplit: Bool) -> Binding<Item?> {
        Binding(
            get: { isSplit ? nil : openItem },
            set: { newValue in if !isSplit { openItem = newValue } }
        )
    }

    // MARK: - Panes

    /// The gap between panes: the hinge, or a 1 pt band with no line (a hairline under Increase Contrast).
    private func band(_ geometry: SplitGeometry) -> some View {
        Rectangle()
            .fill(contrast == .increased && !geometry.isHinge ? Color.secondary : Color.clear)
            .frame(width: geometry.bandWidth)
            .accessibilityHidden(true)
    }

    private var trailingPane: some View {
        NavigationStack {
            Group {
                if let openItem {
                    detail(openItem)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                SheetCloseButton(identifier: "split.close") { self.openItem = nil }
                                    .keyboardShortcut(.cancelAction)
                            }
                        }
                        .id(openItem)
                } else {
                    placeholder()
                }
            }
            .pageChrome()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("split.trailing")
    }
}

extension OnDemandSplitStack where Placeholder == EmptyView {
    /// A split page with no placeholder (the trailing pane appears only while an item is open).
    init(
        path: Binding<NavigationPath>, openItem: Binding<Item?>,
        @ViewBuilder root: @escaping () -> Root, @ViewBuilder detail: @escaping (Item) -> Detail
    ) {
        self.init(path: path, openItem: openItem, alwaysSplit: false, root: root, detail: detail, placeholder: { EmptyView() })
    }
}
