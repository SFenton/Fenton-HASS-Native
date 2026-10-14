import SwiftUI

/// Waits for a page's content before showing it, the way the web app does (pattern:
/// `.agents/patterns/content-gate.md`).
///
/// While loading, the content is laid out but hidden and a centered spinner fades in (after a short delay, so a
/// fast load shows no spinner at all). Once `isReady` is true **and** every piece of content that reported itself
/// (images through ``CachedImage``, anything using ``SwiftUICore/View/contentReadiness(_:isReady:)``) is ready, or
/// ``ContentGateModel/Timing/childTimeout`` passes, the spinner fades out and the content fades in. A gate created
/// with `isReady` already true (data from the disk snapshot or a cache) shows content immediately with no
/// animation.
///
/// HIG: [Loading](https://developer.apple.com/design/human-interface-guidelines/loading) (show content as soon as
/// possible; an indeterminate indicator for unknown waits) and
/// [Motion](https://developer.apple.com/design/human-interface-guidelines/motion) (Reduce Motion drops the rise and
/// keeps the fade).
public struct ContentGate<Content: View>: View {
    private var isReady: Bool
    private var content: Content
    @State private var model: ContentGateModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Creates a gate.
    /// - Parameters:
    ///   - page: Names the page in telemetry (`ContentReady` signposts).
    ///   - isReady: Whether the page's data is loaded.
    ///   - content: The page content.
    public init(page: String, isReady: Bool, @ViewBuilder content: () -> Content) {
        self.isReady = isReady
        self.content = content()
        _model = State(initialValue: ContentGateModel(page: page, isReady: isReady))
    }

    private struct Input: Equatable {
        var isReady: Bool
        var settled: Bool
    }

    public var body: some View {
        let phase = model.phase
        ZStack {
            content
                .environment(\.readinessTracker, model.tracker)
                .opacity(phase == .entering || phase == .idle ? 1 : 0)
                .modifier(RiseIn(active: phase != .idle && phase != .entering && !reduceMotion))
                .allowsHitTesting(phase.showsContent)
                .accessibilityHidden(!phase.showsContent)
            if !phase.showsContent {
                ArcSpinner(.page)
                    .opacity(model.spinnerShown && phase == .loading ? 1 : 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("contentGate.spinner")
            }
        }
        .task(id: Input(isReady: isReady, settled: model.tracker.isSettled)) {
            await model.advance(isReady: isReady, reduceMotion: reduceMotion)
        }
    }
}

/// Holds content 4 pt low while hidden so it rises into place as it fades in (web `recipeResultsEnter`).
private struct RiseIn: ViewModifier {
    var active: Bool

    func body(content: Content) -> some View {
        content.offset(y: active ? 4 : 0)
    }
}
