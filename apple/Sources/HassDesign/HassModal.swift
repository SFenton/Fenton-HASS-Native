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
    func modalChrome() -> some View { headerEdgeFade() }

    /// Presents this modal at full height on iPhone with a visible grabber (owner, 2026-10-13: "All modals
    /// (security system, cameras, etc.) need to open to full height on iPhone"). iPad shows its form sheet.
    func hassSheet() -> some View {
        presentationDetents([.large])
            .presentationDragIndicator(.visible)
    }
}
