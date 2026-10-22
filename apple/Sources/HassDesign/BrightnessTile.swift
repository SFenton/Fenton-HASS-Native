import SwiftUI
#if os(iOS)
import UIKit
#endif

/// A dimmable light tile (web `LightBrightnessCard.tsx`, pattern: `.agents/patterns/entity-tile.md`), the light
/// dragger of direction G (`.agents/design/direction-g.md`, Controls).
///
/// Drawn as the warm lit tile whose bright band is the brightness. While dragging, the tile lifts, a "30%" bubble
/// floats over the band's edge and a selection haptic ticks every 10%. Tap flips power, or opens the light's details when ``onOpen`` is set (web `tapAction: 'more-info'`). A
/// horizontal drag sets brightness from where the finger is across the tile and commits on release, as on the
/// web; a vertical drag is left to the scroll view. VoiceOver activates the tap (with a "Turn On/Off" action
/// when tapping opens details) and swipes up or down to step brightness by ``step``.
///
/// Pure UI: callers pass the live percent and receive intents; they send the service calls.
public struct BrightnessTile: View {
    // MARK: - Inputs

    public var title: String
    public var symbol: String
    public var tint: Color
    /// The fill color (the light's `rgb_color`), or `nil` for ``tint``.
    public var fillTint: Color?
    /// Live brightness, 0 when off.
    public var percent: Int
    public var isUnavailable: Bool
    /// Asked to turn the light on (`true`) or off.
    public var onPower: (Bool) -> Void
    /// Asked to set brightness; 0 means off.
    public var onBrightness: (Int) -> Void
    /// When set, a tap opens the light's details (shown with a chevron) instead of flipping power.
    public var onOpen: (() -> Void)?

    /// VoiceOver adjust step, in percent.
    public nonisolated static let step = 10
    /// Optimistic values give way to live state after this long even if the server never echoes them.
    static let pendingTimeout: Duration = .seconds(4)

    @State private var interaction = BrightnessInteraction()
    @State private var pendingTask: Task<Void, Never>?
    @State private var lastDragEnd = ContinuousClock.now - .seconds(1)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Creates a brightness tile.
    public init(
        title: String,
        symbol: String = "lightbulb",
        tint: Color,
        fillTint: Color? = nil,
        percent: Int,
        isUnavailable: Bool = false,
        onPower: @escaping (Bool) -> Void,
        onBrightness: @escaping (Int) -> Void,
        onOpen: (() -> Void)? = nil
    ) {
        self.title = title
        self.symbol = symbol
        self.tint = tint
        self.fillTint = fillTint
        self.percent = percent
        self.isUnavailable = isUnavailable
        self.onPower = onPower
        self.onBrightness = onBrightness
        self.onOpen = onOpen
    }

    // MARK: - Body

    public var body: some View {
        let shown = interaction.shown(live: percent)
        let isDragging = interaction.dragPercent != nil
        return GlassTileFace(
            title: title,
            subtitle: Self.status(percent: shown, isUnavailable: isUnavailable),
            symbol: symbol,
            tint: tint,
            family: .lights,
            isActive: shown > 0 && !isUnavailable,
            isUnavailable: isUnavailable,
            showsChevron: onOpen != nil,
            level: isUnavailable ? nil : Double(shown) / 100,
            levelTint: fillTint
        )
        .overlay {
            GeometryReader { proxy in
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // A short horizontal drag can also end as a tap; it already set the level.
                        guard ContinuousClock.now - lastDragEnd > .milliseconds(300) else { return }
                        tap()
                    }
                    .modifier(BrightnessDrag(
                        width: proxy.size.width, isEnabled: !isUnavailable,
                        changed: { translation, x in
                            interaction.dragChanged(translation: translation, x: x, width: proxy.size.width)
                        },
                        ended: { x in dragEnded(x: x, width: proxy.size.width) },
                        cancelled: { interaction.dragCancelled() }
                    ))
            }
        }
        .overlay(alignment: .topLeading) {
            if isDragging {
                // Positioned from the tile's size without a GeometryReader, and never in the way of the drag.
                Color.clear
                    .overlay(alignment: .topLeading) {
                        BrightnessBubble(percent: shown)
                            .offset(y: -BrightnessBubble.lift - BrightnessBubble.height / 2)
                    }
                    .visualEffect { content, proxy in
                        content.offset(x: Self.bubbleCenter(percent: shown, width: proxy.size.width) - BrightnessBubble.width / 2)
                    }
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        // The tile lifts while dragging (only its shadow with Reduce Motion).
        .scaleEffect(isDragging && !reduceMotion ? 1.03 : 1)
        // No shadow pass at rest: a blurred shadow over the tile's material is an offscreen render on every frame.
        .shadow(color: isDragging ? .black.opacity(0.35) : .clear, radius: isDragging ? 12 : 0, y: isDragging ? 6 : 0)
        .zIndex(isDragging ? 1 : 0)
        .sensoryFeedback(.selection, trigger: Self.hapticStep(interaction.dragPercent)) { old, new in
            old != nil && new != nil
        }
        .allowsHitTesting(!isUnavailable)
        // The band and bubble glide; with Reduce Motion they jump, and only the bubble and shadow fade.
        .motionSafeAnimation(MotionTokens.quick, value: shown)
        .motionSafeAnimation(MotionTokens.quick, reduced: MotionTokens.quick, value: isDragging)
        // Any live report replaces the optimistic value (web `useOptimisticState`).
        .onChange(of: percent) { interaction.pendingPercent = nil }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(Self.status(percent: shown, isUnavailable: isUnavailable))
        .accessibilityHint(Self.hint(percent: shown, isUnavailable: isUnavailable, opensDetails: onOpen != nil))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { tap() }
        .accessibilityActions {
            if onOpen != nil, !isUnavailable {
                Button(shown > 0 ? "Turn Off" : "Turn On") { flip() }
            }
        }
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: send(interaction.adjust(by: Self.step, live: percent, isUnavailable: isUnavailable))
            case .decrement: send(interaction.adjust(by: -Self.step, live: percent, isUnavailable: isUnavailable))
            @unknown default: break
            }
        }
    }

    // MARK: - Intents

    /// A tap: open details when the caller asked for that, else flip power.
    private func tap() {
        if let onOpen { onOpen() } else { flip() }
    }

    private func flip() {
        send(interaction.flip(live: percent, isUnavailable: isUnavailable))
    }

    /// Passes `intent` to the caller and drops the optimistic value after ``pendingTimeout``.
    private func send(_ intent: BrightnessInteraction.Intent?) {
        guard let intent else { return }
        pendingTask?.cancel()
        pendingTask = Task { @MainActor in
            try? await Task.sleep(for: Self.pendingTimeout)
            guard !Task.isCancelled else { return }
            interaction.pendingPercent = nil
        }
        switch intent {
        case .power(let on): onPower(on)
        case .brightness(let value): onBrightness(value)
        }
    }

    private func dragEnded(x: CGFloat, width: CGFloat) {
        let intent = interaction.dragEnded(x: x, width: width, live: percent)
        if intent != nil { lastDragEnd = .now }
        send(intent)
    }

    // MARK: - Pure helpers

    /// Percent for a touch at `x` across a tile `width` wide, clamped to 0...100.
    nonisolated static func percent(atX x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return min(100, max(0, Double(x / width) * 100))
    }

    /// `value` moved by `delta`, clamped to 0...100.
    nonisolated static func stepped(_ value: Int, by delta: Int) -> Int {
        min(100, max(0, value + delta))
    }

    /// The VoiceOver hint: what a double-tap does, then how to adjust.
    nonisolated static func hint(percent: Int, isUnavailable: Bool, opensDetails: Bool) -> String {
        if isUnavailable { return "" }
        let tap = opensDetails ? "Double-tap for details." : "Double-tap to turn \(percent > 0 ? "off" : "on")."
        return tap + " Swipe up or down to adjust brightness."
    }

    /// The 10% step a drag is in, which ticks the haptic as it changes; nil when not dragging.
    nonisolated static func hapticStep(_ dragPercent: Double?) -> Int? {
        dragPercent.map { Int(($0 / 10).rounded(.down)) }
    }

    /// Where the % bubble's centre sits across a tile `width` wide: over the band's edge, kept inside the tile.
    nonisolated static func bubbleCenter(percent: Int, width: CGFloat) -> CGFloat {
        let half = BrightnessBubble.width / 2
        guard width > BrightnessBubble.width else { return width / 2 }
        return min(width - half, max(half, width * CGFloat(percent) / 100))
    }

    /// The tile's status line and accessibility value: `Off`, `45%` or `Unavailable`.
    nonisolated static func status(percent: Int, isUnavailable: Bool) -> String {
        if isUnavailable { return "Unavailable" }
        return percent > 0 ? "\(percent)%" : "Off"
    }
}

/// The "30%" bubble that floats over the band's edge while dragging. VoiceOver hears the tile's value instead.
struct BrightnessBubble: View {
    var percent: Int

    /// The bubble's width, wide enough for "100%".
    nonisolated static let width: CGFloat = 60
    /// The bubble's height.
    nonisolated static let height: CGFloat = 32
    /// How far above the tile's top edge the bubble's centre sits.
    nonisolated static let lift: CGFloat = 24

    var body: some View {
        Text("\(percent)%")
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .frame(width: Self.width, height: Self.height)
            // A fixed dark capsule with white text in every appearance (like the system's volume HUD): over a light
            // sheet the shadow separates it, and over the lit band it stays readable.
            .background(Color(rgb: HassTokens.Palette.sheetCell), in: Capsule())
            .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .accessibilityHidden(true)
    }
}

/// The tile's interaction state, kept apart from the view so tap, drag and adjust are unit-testable.
///
/// It holds the drag in progress and the optimistic value shown until Home Assistant reports back,
/// and turns gestures into the intents the tile passes to its caller.
struct BrightnessInteraction: Equatable {
    /// What the user asked for.
    enum Intent: Equatable {
        case power(Bool)
        case brightness(Int)
    }

    enum DragAxis { case horizontal, vertical }

    var dragPercent: Double?
    var pendingPercent: Int?
    var dragAxis: DragAxis?

    /// The percent to draw: the drag in progress, else the optimistic value, else `live`.
    func shown(live: Int) -> Int {
        if let dragPercent { return Int(dragPercent.rounded()) }
        return pendingPercent ?? live
    }

    /// Tap: off turns on (optimistically full until the restored level arrives), on turns off.
    mutating func flip(live: Int, isUnavailable: Bool) -> Intent? {
        guard !isUnavailable else { return nil }
        let on = shown(live: live) == 0
        pendingPercent = on ? 100 : 0
        return .power(on)
    }

    /// VoiceOver adjust by `delta` percent, clamped; `nil` when nothing changes.
    mutating func adjust(by delta: Int, live: Int, isUnavailable: Bool) -> Intent? {
        guard !isUnavailable else { return nil }
        return commit(BrightnessTile.stepped(shown(live: live), by: delta), live: live)
    }

    /// The first movement picks the axis; only a horizontal drag sets the level.
    mutating func dragChanged(translation: CGSize, x: CGFloat, width: CGFloat) {
        if dragAxis == nil {
            dragAxis = abs(translation.width) >= abs(translation.height) ? .horizontal : .vertical
        }
        guard dragAxis == .horizontal else { return }
        dragPercent = BrightnessTile.percent(atX: x, width: width)
    }

    /// Release: a horizontal drag commits the level under the finger; a vertical one does nothing.
    mutating func dragEnded(x: CGFloat, width: CGFloat, live: Int) -> Intent? {
        defer { dragAxis = nil }
        guard dragAxis == .horizontal, dragPercent != nil else { return nil }
        dragPercent = nil
        return commit(Int(BrightnessTile.percent(atX: x, width: width).rounded()), live: live)
    }

    /// The system took the touch (a scroll won, or the tile went away): drop the drag without committing.
    mutating func dragCancelled() {
        dragAxis = nil
        dragPercent = nil
    }

    private mutating func commit(_ value: Int, live: Int) -> Intent? {
        guard value != shown(live: live) else { return nil }
        pendingPercent = value
        return .brightness(value)
    }
}

// MARK: - Drag

/// Wires a horizontal drag to the tile without stealing vertical scrolls.
///
/// From iOS 18 a SwiftUI `DragGesture` attached inside a `ScrollView` (even as a simultaneous gesture) keeps the
/// scroll view from scrolling when the drag starts on the tile, so a page of tiles could not be scrolled from them.
/// On iOS a UIKit pan that only begins on a mostly horizontal movement sets brightness and leaves vertical
/// movement to the scroll view; elsewhere the SwiftUI drag remains.
struct BrightnessDrag: ViewModifier {
    var width: CGFloat
    var isEnabled: Bool
    var changed: (CGSize, CGFloat) -> Void
    var ended: (CGFloat) -> Void
    var cancelled: () -> Void

    func body(content: Content) -> some View {
        #if os(iOS)
        if #available(iOS 18.0, *) {
            content.gesture(HorizontalPan(isEnabled: isEnabled, changed: changed, ended: ended, cancelled: cancelled))
        } else {
            content.simultaneousGesture(swiftUIDrag, including: isEnabled ? .all : .none)
        }
        #else
        content.simultaneousGesture(swiftUIDrag, including: isEnabled ? .all : .none)
        #endif
    }

    private var swiftUIDrag: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { changed($0.translation, $0.location.x) }
            .onEnded { ended($0.location.x) }
    }
}

#if os(iOS)
/// A pan that begins only when the finger moves more sideways than up or down.
@available(iOS 18.0, *)
struct HorizontalPan: UIGestureRecognizerRepresentable {
    var isEnabled: Bool
    var changed: (CGSize, CGFloat) -> Void
    var ended: (CGFloat) -> Void
    var cancelled: () -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        pan.isEnabled = isEnabled
        return pan
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        recognizer.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let x = context.converter.localLocation.x
        switch recognizer.state {
        case .began, .changed:
            let moved = context.converter.localTranslation ?? .zero
            changed(CGSize(width: moved.x, height: moved.y), x)
        case .ended: ended(x)
        case .cancelled, .failed: cancelled()
        default: break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y)
        }
    }
}
#endif
