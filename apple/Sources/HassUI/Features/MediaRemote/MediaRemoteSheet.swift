import HassCore
import HassDesign
import SwiftUI

/// The media remote sheet (pattern: `.agents/patterns/media-remote.md`; web `MediaRemoteModalContent.tsx`).
///
/// Direction G (`.agents/design/direction-g.md`, Sheets and Controls: Remote): the sections the remote has (Remote,
/// Apps, Devices, Hue Sync) sit in the bottom glass section bar. Remote shows the 3×3 pad (power in its top-right
/// cell), the volume card and the transport keys; the other sections show only their content. Where a split is
/// allowed (iPad and unfolded iPhone Duo in landscape) and the sheet is wide enough, the pad stays in a leading
/// column and the section scrolls in the trailing one; everywhere else it is one column (HIG: Layout, Sheets). A
/// ``ContentGate`` shows a centered spinner until every app's artwork (all sections) has loaded into the
/// ``ImagePipeline``, then fades the whole content in at once.
public struct MediaRemoteSheet: View {
    @State private var controller: MediaRemoteController
    @State private var tab: MediaRemoteTab
    /// The inline keyboard, opened from the pad's keyboard key and shown in the Remote section.
    @State private var keyboard = KeyboardPrompt()
    @State private var window = WindowMetrics()
    /// Whether the sheet's artwork has settled; until then a centered spinner stands in for the content.
    @State private var isReady: Bool
    private let imageBaseURL: HassServer?
    private let pipeline: ImagePipeline
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
    init(controller: MediaRemoteController, imageServer: HassServer?, initialTab: MediaRemoteTab, window: WindowMetrics? = nil,
         pipeline: ImagePipeline = .shared) {
        _controller = State(initialValue: controller)
        _tab = State(initialValue: controller.config.tabs.contains(initialTab) ? initialTab : .controls)
        _window = State(initialValue: window ?? WindowMetrics())
        imageBaseURL = imageServer
        self.pipeline = pipeline
        // Artwork already decoded in memory (a reopen) shows at once, with no spinner and no fade.
        _isReady = State(initialValue: Self.artworkURLs(controller.config, server: imageServer)
            .allSatisfy { pipeline.memoryImage(for: $0) != nil })
    }

    /// The longest side app artwork is decoded at: the largest tile (168 pt) at 3x, bucketed.
    nonisolated static let artworkPixels = ImagePipeline.bucket(504)

    /// Loads every URL into the image pipeline's memory cache, returning when all have loaded or failed, or after
    /// `timeout`; loads still running then keep going and fill their tiles when they land.
    nonisolated static func prefetch(_ urls: [URL], pipeline: ImagePipeline, timeout: Duration = .seconds(4)) async {
        guard !urls.isEmpty else { return }
        let pixels = artworkPixels
        let loads = Task.detached(priority: .userInitiated) {
            await withTaskGroup(of: Void.self) { group in
                for url in urls {
                    group.addTask {
                        for await _ in pipeline.images(for: url, maxPixel: pixels) { return }
                    }
                }
            }
        }
        let deadline = Task { try? await Task.sleep(for: timeout) }
        // Whichever ends first: a task group would also wait for its slower child.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let once = ResumeOnce(continuation)
            Task { await loads.value; once.resume() }
            Task { await deadline.value; once.resume() }
        }
        deadline.cancel()
    }

    /// Every app tile's artwork, across all tabs, so switching tabs never shows a tile loading.
    static func artworkURLs(_ config: MediaRemoteConfig, server: HassServer?) -> [URL] {
        guard let server else { return [] }
        return config.apps.compactMap { $0.imagePath.map(server.url) }
    }

    /// The line under the title: the media player's app and state ("Plex · Playing"), or its state alone.
    static func subtitle(_ player: EntityState?) -> String? {
        guard let player else { return nil }
        let state = MediaRemoteState.format(player.state)
        guard !MediaRemoteState.isOff(player.state), let app = player.attributes["app_name"]?.string, !app.isEmpty else { return state }
        return "\(app) · \(state)"
    }

    /// Creates the sheet on the app's connection.
    public init(config: MediaRemoteConfig, connection: HassConnection, initialTab: MediaRemoteTab = .controls) {
        self.init(config: config, store: connection.store, caller: connection, imageServer: connection.server, initialTab: initialTab)
    }

    public var body: some View {
        NavigationStack {
            ContentGate(page: "Media Remote", isReady: isReady) {
                layout
            }
            .background { WindowMetricsReader(metrics: $window) }
            .modalChrome()
            .modifier(RemoteSectionBar(tabs: controller.config.tabs, title: controller.config.remoteTitle, selection: $tab))
            .navigationTitle(controller.config.title)
            .sheetSubtitle(Self.subtitle(controller.store.entity(controller.config.mediaEntityId).state))
            .inlineNavigationTitle()
            .toolbar { SheetCloseItem { dismiss() } }
        }
        .task {
            guard !isReady else { return }
            await Self.prefetch(Self.artworkURLs(controller.config, server: imageBaseURL), pipeline: pipeline)
            isReady = true
        }
    }

    private var layout: some View {
        GeometryReader { proxy in
            let twoColumns = MediaRemoteLayout.usesTwoColumns(
                window: window.size ?? proxy.size, isRegularWidth: window.isRegularWidth, container: proxy.size)
            Group {
                if twoColumns {
                    HStack(alignment: .top, spacing: 0) {
                        ScrollView {
                            pad(width: proxy.size.width / 2 - 2 * HassTokens.Spacing.l)
                                .padding(HassTokens.Spacing.l)
                        }
                        .frame(width: proxy.size.width / 2)
                        section(includesPad: false)
                            .frame(width: proxy.size.width / 2)
                    }
                } else {
                    section(includesPad: true)
                }
            }
            .accessibilityIdentifier(twoColumns ? "remote.layout.twoColumn" : "remote.layout.singleColumn")
        }
    }

    // MARK: - Columns

    private func pad(width: CGFloat?) -> some View {
        DirectionalPad(controller: controller, maxWidth: width, keyboardOpen: keyboard.isOpen) { target in
            keyboard.toggle(target)
            // The field lives in the Remote section; in two columns another section may be showing.
            if keyboard.isOpen { tab = .controls }
        }
        .frame(maxWidth: .infinity)
    }

    /// The selected section. Remote and Apps scroll in one column; Devices and Hue Sync are inset grouped lists,
    /// which scroll themselves.
    @ViewBuilder
    private func section(includesPad: Bool) -> some View {
        switch tab {
        case .controls:
            RemoteScroll {
                VStack(spacing: HassTokens.Spacing.xl) {
                    if includesPad { pad(width: nil) }
                    RemoteControlsTab(controller: controller, keyboard: $keyboard)
                }
            }
        case .apps:
            RemoteScroll { RemoteAppsTab(controller: controller, imageServer: imageBaseURL) }
        case .devices:
            RemoteDevicesTab(controller: controller)
        case .hueSync:
            if let hue = controller.config.hueSync { HueSyncTab(controller: controller, hue: hue) }
        }
    }
}

/// One scrolling column, at most 640 pt wide and centred.
private struct RemoteScroll<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            content
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
                .padding(HassTokens.Spacing.l)
        }
    }
}

/// The remote's sections in the bottom glass section bar (``ModalTabBar``), when it has more than one.
private struct RemoteSectionBar: ViewModifier {
    var tabs: [MediaRemoteTab]
    var title: String
    @Binding var selection: MediaRemoteTab

    func body(content: Content) -> some View {
        if tabs.count > 1 {
            content.modalTabBar(tabs, label: "\(title) sections", title: \.title,
                                  symbol: ModalTabSymbols.symbol(for:), selection: $selection, identifier: "remote.tabs")
        } else {
            content
        }
    }
}

// MARK: - Layout policy

/// When the remote uses two columns (owner's split rules, `.agents/design/apple/split-view.md`).
enum MediaRemoteLayout {
    /// The narrowest sheet that holds the d-pad column beside the tab content.
    static let minimumTwoColumnWidth: CGFloat = 640

    /// Two columns only where the window may split (landscape, regular width) and the sheet is wide enough.
    static func usesTwoColumns(window: CGSize, isRegularWidth: Bool, container: CGSize) -> Bool {
        SplitPolicy.allowsSplit(size: window, isRegularWidth: isRegularWidth) && container.width >= minimumTwoColumnWidth
    }
}

/// Resumes a continuation the first time it is asked to.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?

    init(_ continuation: CheckedContinuation<Void, Never>) { self.continuation = continuation }

    func resume() {
        let pending = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            defer { continuation = nil }
            return continuation
        }
        pending?.resume()
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
            Task { @MainActor in if self.metrics != metrics { self.metrics = metrics } }
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
