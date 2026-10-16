import SwiftUI

// MARK: - Create and edit sheets

/// The leading Cancel on a create or edit sheet: an x in a glass circle that drops the draft
/// (`.agents/design/direction-g.md`, Sheets: "circle x Cancel leading and a filled `#0071E3` checkmark trailing, as in
/// Calendar and Reminders"). Viewing sheets use ``SheetCloseItem`` instead.
///
/// iOS 26 and later draw the system cancel glyph (`Button(role: .cancel)`); earlier systems draw an `xmark` symbol.
/// VoiceOver reads "Cancel". HIG Toolbars: "prefer their standard symbols without text labels".
public struct SheetCancelItem: ToolbarContent {
    private let identifier: String
    private let isEnabled: Bool
    private let action: () -> Void

    /// Creates the item.
    /// - Parameters:
    ///   - identifier: Accessibility identifier; sheets keep their existing one so UI tests stay stable.
    ///   - isEnabled: False while a save is in flight.
    ///   - action: Drops the draft and dismisses the sheet.
    public init(identifier: String = "sheet.cancel", isEnabled: Bool = true, action: @escaping () -> Void) {
        self.identifier = identifier
        self.isEnabled = isEnabled
        self.action = action
    }

    public var body: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Group {
                if #available(iOS 26.0, macOS 26.0, watchOS 26.0, *) {
                    Button(role: .cancel, action: action)
                } else {
                    Button(action: action) {
                        Label("Cancel", systemImage: "xmark")
                    }
                    .labelStyle(.iconOnly)
                }
            }
            .disabled(!isEnabled)
            .accessibilityLabel("Cancel")
            .accessibilityIdentifier(identifier)
        }
    }
}

/// The trailing confirm on a create or edit sheet: a checkmark on G's filled `#0071E3` circle
/// (``HassTokens/Ink/actionFill``, 4.6:1 under white). While the save is in flight it shows an inline ``ArcSpinner``
/// and is spoken as the action in progress ("Saving").
///
/// iOS 26 and later use `Button(role: .confirm)`, which the system draws prominent on glass; earlier systems draw a
/// bordered-prominent circle.
public struct SheetConfirmItem: ToolbarContent {
    private let title: String
    private let busyTitle: String?
    private let isBusy: Bool
    private let isEnabled: Bool
    private let identifier: String
    private let action: () -> Void

    /// Creates the item.
    /// - Parameters:
    ///   - title: What the check does, spoken by VoiceOver: "Save", "Add", "Create" or "Apply".
    ///   - isEnabled: False while the draft can't be saved (an empty name, nothing changed).
    ///   - isBusy: Shows the spinner in place of the check, which is disabled meanwhile.
    ///   - busyTitle: Spoken while busy ("Saving"); defaults to the title.
    ///   - identifier: Accessibility identifier; sheets keep their existing one so UI tests stay stable.
    ///   - action: Commits the draft.
    public init(_ title: String, isEnabled: Bool = true, isBusy: Bool = false, busyTitle: String? = nil,
                identifier: String = "sheet.confirm", action: @escaping () -> Void) {
        self.title = title
        self.isEnabled = isEnabled
        self.isBusy = isBusy
        self.busyTitle = busyTitle
        self.identifier = identifier
        self.action = action
    }

    public var body: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            SheetConfirmButton(title: title, busyTitle: busyTitle, isBusy: isBusy, action: action)
                .disabled(!isEnabled || isBusy)
                .accessibilityIdentifier(identifier)
        }
    }
}

/// The confirm button itself (``SheetConfirmItem``).
private struct SheetConfirmButton: View {
    var title: String
    var busyTitle: String?
    var isBusy: Bool
    var action: () -> Void

    var body: some View {
        Group {
            if isBusy {
                ArcSpinner(.inline, label: busyTitle ?? title)
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(HassTokens.Ink.actionFill, in: Circle())
            } else if #available(iOS 26.0, macOS 26.0, watchOS 26.0, *) {
                Button(role: .confirm, action: action)
                    .tint(HassTokens.Ink.actionFill)
                    .accessibilityLabel(title)
            } else {
                Button(action: action) {
                    Label(title, systemImage: "checkmark")
                        .labelStyle(.iconOnly)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .tint(HassTokens.Ink.actionFill)
                .accessibilityLabel(title)
            }
        }
    }
}

#Preview("Edit sheet toolbar") {
    NavigationStack {
        Form { TextField("Task Name", text: .constant("Replace the furnace filter")) }
            .navigationTitle("New Task")
            .toolbar {
                SheetCancelItem {}
                SheetConfirmItem("Create") {}
            }
    }
    .preferredColorScheme(.dark)
}
