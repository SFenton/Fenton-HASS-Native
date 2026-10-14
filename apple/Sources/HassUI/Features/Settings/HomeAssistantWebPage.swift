import HassCore
import HassDesign
import SwiftUI
#if os(iOS)
import WebKit
#endif

/// One of Home Assistant's own pages (Settings or Profile), signed in with the app's session.
///
/// Tokens are handed over through ``FrontendSession`` into a non-persistent web data store, so they
/// never reach disk and vanish when the page closes. Links to other sites open in the browser.
struct HomeAssistantWebPage: View {
    var page: HomeAssistantSettingsView.WebPage

    @Environment(AppSession.self) private var session
    @Environment(HassConnection.self) private var connection
    @State private var frontend: FrontendSession?
    @State private var failed = false
    @State private var isLoading = true
    @State private var reloadToken = 0

    /// Creates the page; `frontend` and `failed` seed its state (hosted tests).
    init(page: HomeAssistantSettingsView.WebPage, frontend: FrontendSession? = nil, failed: Bool = false) {
        self.page = page
        _frontend = State(initialValue: frontend)
        _failed = State(initialValue: failed)
    }

    var body: some View {
        content
            .navigationTitle(page.title)
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { reloadToken += 1 } label: { Label("Reload", systemImage: "arrow.clockwise") }
                        .disabled(frontend == nil)
                        .accessibilityIdentifier("haWeb.reload")
                }
            }
            .task { await prepare() }
    }

    @ViewBuilder
    private var content: some View {
        if failed {
            ContentUnavailableView {
                Label("Can't open \(page.title)", systemImage: "wifi.exclamationmark")
            } description: {
                Text("Home Assistant couldn't be reached. Check your connection and try again.")
            } actions: {
                Button("Try Again") { Task { await prepare() } }
                    .accessibilityIdentifier("haWeb.retry")
            }
        } else if let frontend {
            #if os(iOS)
            HassWebView(session: frontend, path: page.path, reloadToken: reloadToken, isLoading: $isLoading, failed: $failed)
                .ignoresSafeArea(edges: .bottom)
                .overlay { if isLoading { ProgressView("Loading \(page.title)…").progressViewStyle(.arc) } }
                .accessibilityIdentifier("haWeb.\(page.rawValue)")
            #else
            Text(frontend.origin + page.path)
            #endif
        } else {
            ProgressView("Loading \(page.title)…").progressViewStyle(.arc)
        }
    }

    private func prepare() async {
        failed = false
        frontend = await Self.frontendSession(server: connection.server, tokens: session.tokens)
        failed = frontend == nil
    }

    /// The sign-in hand-off for the web view, with fresh tokens; `nil` when signed out or the refresh fails.
    static func frontendSession(server: HassServer, tokens: TokenManager?) async -> FrontendSession? {
        guard let tokens, let current = try? await tokens.validTokens() else { return nil }
        return FrontendSession(server: server, tokens: current)
    }
}

#if os(iOS)
/// `WKWebView` host for ``HomeAssistantWebPage``.
struct HassWebView: UIViewRepresentable {
    var session: FrontendSession
    var path: String
    var reloadToken: Int
    @Binding var isLoading: Bool
    @Binding var failed: Bool

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        if let script = try? session.bootstrapScript() {
            configuration.userContentController.addUserScript(
                WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true)
            )
        }
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        context.coordinator.lastReload = reloadToken
        webView.load(URLRequest(url: session.server.url(path)))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.lastReload != reloadToken {
            context.coordinator.lastReload = reloadToken
            webView.reload()
        }
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: HassWebView
        var lastReload = 0

        init(parent: HassWebView) { self.parent = parent }

        func webView(
            _ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
            decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = action.request.url else { return decisionHandler(.cancel) }
            if parent.session.isInternal(url) { return decisionHandler(.allow) }
            // Anything off the server (docs, integrations' sites) opens in the browser.
            if action.targetFrame?.isMainFrame ?? true { UIApplication.shared.open(url) }
            decisionHandler(.cancel)
        }

        /// `target="_blank"` links: same-server pages load here, others go to the browser.
        func webView(
            _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
            for action: WKNavigationAction, windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if let url = action.request.url {
                if parent.session.isInternal(url) { webView.load(action.request) } else { UIApplication.shared.open(url) }
            }
            return nil
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.isLoading = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            fail(error)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            fail(error)
        }

        private func fail(_ error: Error) {
            parent.isLoading = false
            if (error as NSError).code == NSURLErrorCancelled { return }
            parent.failed = true
        }
    }
}
#endif
