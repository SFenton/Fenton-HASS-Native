import HassCore
import HassDesign
import SwiftUI

/// The media remote sheet (pattern: `.agents/patterns/media-remote.md`; web `MediaRemoteModalContent.tsx`).
///
/// Power and the d-pad are always visible; a segmented control picks between the tabs that have content.
/// Where a split is allowed (iPad and unfolded iPhone Duo in landscape) and the sheet is wide enough, power and
/// the d-pad move to a leading column and the tab content scrolls in the trailing one; everywhere else it is
/// one scrolling column (HIG: Layout, Sheets).
public struct MediaRemoteSheet: View {
    @State private var controller: MediaRemoteController
    @State private var tab: MediaRemoteTab
    @State private var window = WindowMetrics()
    private let imageBaseURL: HassServer?
    @Environment(\.dismiss) private var dismiss

    /// Creates the sheet.
    /// - Parameters:
    ///   - config: The remote.
    ///   - store: Live entity state.
    ///   - caller: Where service calls go (the connection, or a recorder in tests).
    ///   - imageServer: Serves app artwork from `/local/images/apps`; `nil` shows icon fallbacks.
    ///   - initialTab: The tab shown first; falls back to Controls when the remote has no such tab.
    public init(
        config: MediaRemoteConfig, store: EntityStore, caller: any HassServiceCalling,
        imageServer: HassServer? = nil, initialTab: MediaRemoteTab = .controls
    ) {
        self.init(controller: MediaRemoteController(config: config, store: store, caller: caller),
                  imageServer: imageServer, initialTab: initialTab)
    }

    /// Creates the sheet on an existing controller; `window` stands in for the hosting window in hosted tests.
    init(controller: MediaRemoteController, imageServer: HassServer?, initialTab: MediaRemoteTab, window: WindowMetrics? = nil) {
        _controller = State(initialValue: controller)
        _tab = State(initialValue: controller.config.tabs.contains(initialTab) ? initialTab : .controls)
        _window = State(initialValue: window ?? WindowMetrics())
        imageBaseURL = imageServer
    }

    /// Creates the sheet on the app's connection.
    public init(config: MediaRemoteConfig, connection: HassConnection, initialTab: MediaRemoteTab = .controls) {
        self.init(config: config, store: connection.store, caller: connection, imageServer: connection.server, initialTab: initialTab)
    }

    public var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let twoColumns = MediaRemoteLayout.usesTwoColumns(
                    window: window.size ?? proxy.size, isRegularWidth: window.isRegularWidth, container: proxy.size)
                Group {
                    if twoColumns {
                        HStack(alignment: .top, spacing: 0) {
                            ScrollView { leadingColumn.padding(HassTokens.Spacing.l) }
                                .frame(width: proxy.size.width / 2)
                                .accessibilityIdentifier("remote.leadingColumn")
                            ScrollViewReader { reader in
                                ScrollView { tabColumn(reader: reader).padding(HassTokens.Spacing.l) }
                            }
                            .frame(width: proxy.size.width / 2)
                        }
                    } else {
                        ScrollViewReader { reader in
                            ScrollView {
                                VStack(spacing: HassTokens.Spacing.xl) {
                                    leadingColumn
                                    tabColumn(reader: reader)
                                }
                                .frame(maxWidth: 640)
                                .frame(maxWidth: .infinity)
                                .padding(HassTokens.Spacing.l)
                            }
                        }
                    }
                }
                .accessibilityIdentifier(twoColumns ? "remote.layout.twoColumn" : "remote.layout.singleColumn")
            }
            .background { WindowMetricsReader(metrics: $window) }
            .navigationTitle(controller.config.title)
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    // MARK: - Columns

    private var leadingColumn: some View {
        VStack(spacing: HassTokens.Spacing.xl) {
            PowerPill(controller: controller)
            DirectionalPad(controller: controller)
        }
        .frame(maxWidth: .infinity)
    }

    private func tabColumn(reader: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.xl) {
            if controller.config.tabs.count > 1 {
                RemoteTabPicker(tabs: controller.config.tabs, title: controller.config.remoteTitle, selection: $tab)
                    .id(MediaRemoteLayout.tabTopID)
            }
            switch tab {
            case .controls: RemoteControlsTab(controller: controller)
            case .apps: RemoteAppsTab(controller: controller, imageServer: imageBaseURL)
            case .devices: RemoteDevicesTab(controller: controller)
            case .hueSync:
                if let hue = controller.config.hueSync { HueSyncTab(controller: controller, hue: hue) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: tab) { _, _ in reader.scrollTo(MediaRemoteLayout.tabTopID, anchor: .top) }
    }
}

// MARK: - Presentation

public extension View {
    /// Presents a remote sheet the way the pattern requires: full height, drag indicator visible, and a page-size
    /// sheet on iPad so the landscape layout has room for two columns.
    func mediaRemotePresentation() -> some View {
        modifier(MediaRemotePresentation())
    }
}

private struct MediaRemotePresentation: ViewModifier {
    func body(content: Content) -> some View {
        let sheet = content
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        if #available(iOS 18.0, macOS 15.0, *) {
            sheet.presentationSizing(.page)
        } else {
            sheet
        }
    }
}

// MARK: - Layout policy

/// When the remote uses two columns (owner's split rules, `.agents/design/apple/split-view.md`).
enum MediaRemoteLayout {
    /// The narrowest sheet that holds the d-pad column beside the tab content.
    static let minimumTwoColumnWidth: CGFloat = 640

    /// Scroll anchor at the top of the tab column.
    static let tabTopID = "remote.tabTop"

    /// Two columns only where the window may split (landscape, regular width) and the sheet is wide enough.
    static func usesTwoColumns(window: CGSize, isRegularWidth: Bool, container: CGSize) -> Bool {
        SplitPolicy.allowsSplit(size: window, isRegularWidth: isRegularWidth) && container.width >= minimumTwoColumnWidth
    }
}

/// The window the sheet is in. A sheet's own size class is compact on iPad, so layout decisions read the window.
struct WindowMetrics: Equatable {
    var size: CGSize?
    var isRegularWidth = false
}

#if os(iOS)
/// Reports the hosting window's size and width class.
struct WindowMetricsReader: UIViewRepresentable {
    @Binding var metrics: WindowMetrics

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.isUserInteractionEnabled = false
        view.onChange = { metrics in
            DispatchQueue.main.async { if self.metrics != metrics { self.metrics = metrics } }
        }
        return view
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {}

    final class ProbeView: UIView {
        var onChange: ((WindowMetrics) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            report()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            report()
        }

        private func report() {
            guard let window else { return }
            onChange?(WindowMetrics(size: window.bounds.size, isRegularWidth: window.traitCollection.horizontalSizeClass == .regular))
        }
    }
}
#else
/// macOS (hosted tests): the sheet's own size decides.
struct WindowMetricsReader: View {
    @Binding var metrics: WindowMetrics
    var body: some View { Color.clear }
}
#endif
