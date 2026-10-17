import SwiftUI

// MARK: - Close

/// The Close button every modal carries at the top trailing edge (pattern: `.agents/patterns/modal-sheet.md`;
/// owner, 2026-10-13: "'Done' button in top right can just be 'circle X' close button like FestivalNativeApps").
///
/// iOS 26 and later draw the system close glyph (`Button(role: .close)`), an X in a glass circle; earlier
/// systems draw an `xmark` symbol. VoiceOver reads "Close". HIG Toolbars: "Close dismisses a modal; prefer
/// their standard symbols without text labels." A sheet that saves (a form with Save or Add) keeps its own
/// confirmation button and uses this only to leave.
public struct SheetCloseItem: ToolbarContent {
    private let identifier: String
    private let action: () -> Void

    /// Creates the item.
    /// - Parameters:
    ///   - identifier: Accessibility identifier; sheets keep their existing one so UI tests stay stable.
    ///   - action: Dismisses the modal.
    public init(identifier: String = "sheet.close", action: @escaping () -> Void) {
        self.identifier = identifier
        self.action = action
    }

    public var body: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            SheetCloseButton(identifier: identifier, action: action)
        }
    }
}

/// The Close button itself, for places that are not a toolbar item (a split pane's own bar).
public struct SheetCloseButton: View {
    var identifier: String
    var action: () -> Void

    /// Creates the button.
    public init(identifier: String = "sheet.close", action: @escaping () -> Void) {
        self.identifier = identifier
        self.action = action
    }

    public var body: some View {
        Group {
            if #available(iOS 26.0, macOS 26.0, watchOS 26.0, *) {
                Button(role: .close, action: action)
            } else {
                Button(action: action) {
                    Label("Close", systemImage: "xmark")
                }
                .labelStyle(.iconOnly)
            }
        }
        .accessibilityLabel("Close")
        .accessibilityIdentifier(identifier)
    }
}

// MARK: - Modal container

/// The container a modal is built from: a `NavigationStack` with an inline title, the circle-X close
/// (``SheetCloseItem``) and content that fades out under the header (``SwiftUI/View/modalChrome()``), with no
/// translucent band behind it (FestivalNativeApps `FestivalModal`).
///
/// ```swift
/// HassModal("Security System", closeIdentifier: "security.sheet.close") {
///     SecuritySystemContent()
/// }
/// .hassSheet()
/// ```
///
/// Pages pushed inside the modal apply ``SwiftUI/View/modalChrome()`` themselves so their content fades too.
public struct HassModal<Content: View>: View {
    private let title: String
    private let closeIdentifier: String
    private let onClose: (() -> Void)?
    private let content: Content
    @Environment(\.dismiss) private var dismiss

    /// Creates a modal.
    /// - Parameters:
    ///   - title: Inline navigation title, which VoiceOver announces first.
    ///   - closeIdentifier: Accessibility identifier of the Close button.
    ///   - onClose: Runs instead of the environment `dismiss` when the presenter owns closing.
    ///   - content: The modal's root view, placed inside the navigation stack.
    public init(_ title: String, closeIdentifier: String = "sheet.close", onClose: (() -> Void)? = nil,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.closeIdentifier = closeIdentifier
        self.onClose = onClose
        self.content = content()
    }

    public var body: some View {
        NavigationStack {
            content
                .modalChrome()
                .navigationTitle(title)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar { SheetCloseItem(identifier: closeIdentifier) { onClose?() ?? dismiss() } }
        }
        // Sheets follow the system appearance while pages stay dark (``SystemAppearance``).
        .followsSystemAppearance()
    }
}

public extension View {
    /// The header treatment of a page inside a modal: no translucent band behind the header, and content that
    /// fades out before it reaches it (``HeaderEdgeFade``). ``HassModal`` applies it to its root; apply it to a
    /// modal's own root and to each page pushed inside a modal.
    ///
    /// The page's background (the grouped background, behind lists and plain content alike) fills the whole
    /// sheet, header included, outside the fade, so the header never reads as a band of another color.
    func modalChrome() -> some View {
        headerEdgeFade()
            // Modal titles are inline, and a pinned `modalTabBar` belongs to the header: never cap it at the
            // window's bar height.
            .environment(\.headerEdgeCap, nil)
            // Dark tiles in a sheet sit on the sheet's cell colour rather than the page module (direction G).
            .environment(\.tileSurface, .sheet)
            .scrollContentBackground(.hidden)
            .background { ModalBackground().ignoresSafeArea() }
            // Tells a fitted sheet how tall this page's content is (``SheetFit``).
            .reportsSheetFit()
    }

    /// Presents this modal, sized to its content on iPhone, with a visible grabber, in the system appearance while the
    /// pages behind stay dark (``SwiftUICore/View/followsSystemAppearance()``). The one sheet sizing API.
    ///
    /// **Height (owner, 2026-10-16, replacing 2026-10-13's "all modals full height").** A sheet opens only as tall as it
    /// needs (``HassSheetHeight/fitted``, the default): the page's scroll content is measured (``SheetFit``) and the
    /// detent follows it, capped at large, recomputed when the content or Dynamic Type changes. Pass
    /// ``HassSheetHeight/full`` for a remote, any modal with a section tab bar, a sheet that navigates between pages
    /// and a sheet over live video; their height must not change with a tab or a pushed page. Recipe detail stays full
    /// screen.
    ///
    /// **Width (iPad).** Every sheet names its size (plan Phase 4, decision 4; HIG: Sheets, "Prefer page or form
    /// sheet styles in an iPadOS app"): `.page` for viewing and control sheets with tile grids, dials, maps or a second
    /// column, `.form` for lists, editors and prompts. The default is `.form`, so a sheet that forgets still gets a
    /// narrow, readable sheet rather than the system's full-screen-ish default.
    /// - Parameters:
    ///   - width: The iPad sheet size: a form sheet or a page sheet. No effect on iPhone.
    ///   - height: Content-fitted (default) or full height.
    ///   - appearance: Follow the system (default), or stay dark for a sheet drawn over a photo or gradient (Weather).
    ///   - fitKey: Identifies this sheet so its measured height is remembered for the next time it opens. Leave the
    ///     default, the call site.
    func hassSheet(_ width: HassSheetWidth = .form, height: HassSheetHeight = .fitted,
                   appearance: HassSheetAppearance = .system,
                   fitKey: String = "\(#fileID):\(#line)") -> some View {
        modifier(HassSheetPresentation(width: width, height: height, appearance: appearance, fitKey: fitKey))
    }

    /// Only the iPad sheet size, for sheets that keep their own detents. iOS 18 and later; earlier systems keep the
    /// system's size.
    /// - Parameter width: The iPad sheet size.
    func hassSheetSizing(_ width: HassSheetWidth) -> some View {
        modifier(HassSheetSizing(width: width, fitsHeight: false))
    }
}

/// How wide a ``SwiftUI/View/hassSheet(_:height:appearance:fitKey:)`` modal is on iPad.
public enum HassSheetWidth: Sendable, Equatable {
    /// A form sheet (540 pt): lists, editors, prompts, short device controls.
    case form
    /// A page sheet, with room for tile grids, dials, maps and two columns.
    case page
}

/// How a ``SwiftUI/View/hassSheet(_:height:appearance:fitKey:)`` modal chooses light or dark.
public enum HassSheetAppearance: Sendable {
    /// The user's system appearance (``SystemAppearance``): light or dark.
    case system
    /// Always dark: a sheet whose backdrop is a photo or gradient (Weather).
    case dark
}

/// Implementation of ``SwiftUI/View/hassSheet(_:height:appearance:fitKey:)``.
private struct HassSheetPresentation: ViewModifier {
    var width: HassSheetWidth
    var height: HassSheetHeight
    var appearance: HassSheetAppearance
    var fitKey: String

    func body(content: Content) -> some View {
        content
            .modifier(SheetAppearanceModifier(appearance: appearance))
            .presentationDragIndicator(.visible)
            // Opaque ground at every detent: a partial-height sheet is glass on iOS 26 and let a page's coloured tiles
            // show through (HIG: Sheets; Accessibility, Color and effects). A dark-by-design sheet keeps its own.
            .modifier(SheetGroundModifier(appearance: appearance))
            // Inside the height modifier, which publishes the measurement the iPad sizing reads.
            .modifier(HassSheetSizing(width: width, fitsHeight: height == .fitted))
            .modifier(SheetHeightModifier(height: height, fitKey: fitKey))
    }
}

/// Implementation of ``SwiftUI/View/hassSheetSizing(_:)``.
private struct HassSheetSizing: ViewModifier {
    var width: HassSheetWidth
    /// iPad: size the sheet's height to the measured content instead of the form or page sheet's fixed height.
    var fitsHeight: Bool
    @Environment(\.sheetFit) private var fit

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(watchOS)
        content
        #else
        if #available(iOS 18.0, macOS 15.0, *) {
            if fitsHeight, let wanted = fit?.contentHeight {
                // The wanted height as the content's ideal height, which a fitted presentation sizes itself to.
                switch width {
                case .form:
                    content.frame(idealHeight: wanted).presentationSizing(.form.fitted(horizontal: false, vertical: true))
                case .page:
                    content.frame(idealHeight: wanted).presentationSizing(.page.fitted(horizontal: false, vertical: true))
                }
            } else {
                switch width {
                case .form: content.presentationSizing(.form)
                case .page: content.presentationSizing(.page)
                }
            }
        } else {
            content
        }
        #endif
    }
}

/// Applies a sheet's appearance: the system's, or dark. The shell forces dark for the pages behind, so a system sheet
/// states the user's appearance explicitly (``SystemAppearance``).
private struct SheetAppearanceModifier: ViewModifier {
    var appearance: HassSheetAppearance

    @ViewBuilder
    func body(content: Content) -> some View {
        switch appearance {
        case .system: content.followsSystemAppearance()
        case .dark: content.preferredColorScheme(.dark)
        }
    }
}

/// The opaque sheet ground behind the content, so a partial-height sheet never shows the page through glass.
private struct SheetGroundModifier: ViewModifier {
    var appearance: HassSheetAppearance

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(iOS)
        if appearance == .system {
            content.presentationBackground(Color(uiColor: .systemGroupedBackground))
        } else {
            content
        }
        #else
        content
        #endif
    }
}

/// The modal page background: the system grouped background, so rows and tiles on it keep their contrast.
private struct ModalBackground: View {
    var body: some View {
        #if canImport(UIKit)
        Color(uiColor: .systemGroupedBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }
}
