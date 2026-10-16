import SwiftUI

/// Waits for a page's content before showing it, the way the web app does (pattern:
/// `.agents/patterns/content-gate.md`).
///
/// While loading, the content is laid out but hidden and a centered spinner fades in (after a short delay, so a
/// fast load shows no spinner at all). Once `isReady` is true **and** every piece of content that reported itself
/// (images through ``CachedImage``, anything using ``SwiftUICore/View/contentReadiness(_:isReady:)``) is ready, or
/// ``ContentGateModel/Profile/childTimeout`` passes, the spinner fades out and the content fades in. A gate created
/// with `isReady` already true (data from the disk snapshot or a cache) shows content immediately with no
/// animation.
///
/// HIG: [Loading](https://developer.apple.com/design/human-interface-guidelines/loading) (show content as soon as
/// possible; an indeterminate indicator for unknown waits) and
/// [Motion](https://developer.apple.com/design/human-interface-guidelines/motion) (Reduce Motion drops the rise and
/// keeps the fade).
public struct ContentGate<Content: View>: View {
    private var isReady: Bool
    private var label: String
    private var content: Content
    @State private var model: ContentGateModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Creates a gate.
    /// - Parameters:
    ///   - page: Names the page in telemetry (`ContentReady` signposts).
    ///   - isReady: Whether the page's data is loaded.
    ///   - timing: The timings of the first load: ``ContentGateModel/Profile/page`` for a page opening cold,
    ///     ``ContentGateModel/Profile/results`` (the default) for a results region.
    ///   - reloadTiming: The timings of later loads, once the content has shown (defaults to `timing`).
    ///   - label: What VoiceOver says for the spinner ("Loading Pantry").
    ///   - content: The page content.
    public init(
        page: String, isReady: Bool, timing: ContentGateModel.Profile = .results, reloadTiming: ContentGateModel.Profile? = nil,
        label: String = "Loading", @ViewBuilder content: () -> Content
    ) {
        self.isReady = isReady
        self.label = label
        self.content = content()
        _model = State(initialValue: ContentGateModel(page: page, isReady: isReady, firstLoad: timing, reload: reloadTiming))
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
            // Built only while it shows, so a fast load never runs the arc's timeline at all.
            if !phase.showsContent, model.spinnerShown, phase == .loading {
                ArcSpinner(.page, label: label)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
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
