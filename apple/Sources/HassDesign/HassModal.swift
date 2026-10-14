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
            .scrollContentBackground(.hidden)
            .background { ModalBackground().ignoresSafeArea() }
    }

    /// Presents this modal at full height on iPhone with a visible grabber (owner, 2026-10-13: "All modals
    /// (security system, cameras, etc.) need to open to full height on iPhone"), the one sheet sizing API.
    /// - Parameter width: The iPad sheet size: the system default, a form sheet or a page sheet (two-column
    ///   remotes, thermostat and bedroom sheets, the humidifier). No effect on iPhone. HIG: Sheets ("Prefer page
    ///   or form sheet styles in an iPadOS app").
    func hassSheet(_ width: HassSheetWidth = .automatic) -> some View {
        modifier(HassSheetPresentation(width: width))
    }
}

/// How wide a ``SwiftUI/View/hassSheet(_:)`` modal is on iPad.
public enum HassSheetWidth: Sendable {
    /// The system's default for the presentation.
    case automatic
    /// A form sheet (device controls, short forms).
    case form
    /// A page sheet, with room for two columns.
    case page
}

/// Implementation of ``SwiftUI/View/hassSheet(_:)``.
private struct HassSheetPresentation: ViewModifier {
    var width: HassSheetWidth

    func body(content: Content) -> some View {
        let sheet = content
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        #if os(watchOS)
        sheet
        #else
        if #available(iOS 18.0, macOS 15.0, *) {
            switch width {
            case .automatic: sheet
            case .form: sheet.presentationSizing(.form)
            case .page: sheet.presentationSizing(.page)
            }
        } else {
            sheet
        }
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
