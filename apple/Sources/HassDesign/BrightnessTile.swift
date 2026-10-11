import SwiftUI

/// A dimmable light tile (web `LightBrightnessCard.tsx`, pattern: `.agents/patterns/entity-tile.md`).
///
/// Tap flips power. A horizontal drag sets brightness from where the finger is across the tile and
/// commits on release, as on the web; a vertical drag is left to the scroll view. VoiceOver activates
/// to flip power and swipes up or down to step brightness by ``step``.
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

    /// VoiceOver adjust step, in percent.
    public nonisolated static let step = 10
    /// Optimistic values give way to live state after this long even if the server never echoes them.
    static let pendingTimeout: Duration = .seconds(4)

    @State private var interaction = BrightnessInteraction()
    @State private var pendingTask: Task<Void, Never>?
    @State private var lastDragEnd = ContinuousClock.now - .seconds(1)

    /// Creates a brightness tile.
    public init(
        title: String,
        symbol: String = "lightbulb",
        tint: Color,
        fillTint: Color? = nil,
        percent: Int,
        isUnavailable: Bool = false,
        onPower: @escaping (Bool) -> Void,
        onBrightness: @escaping (Int) -> Void
    ) {
        self.title = title
        self.symbol = symbol
        self.tint = tint
        self.fillTint = fillTint
        self.percent = percent
        self.isUnavailable = isUnavailable
        self.onPower = onPower
        self.onBrightness = onBrightness
    }

    // MARK: - Body

    public var body: some View {
        let shown = interaction.shown(live: percent)
        return GlassTileFace(
            title: title,
            subtitle: Self.status(percent: shown, isUnavailable: isUnavailable),
            symbol: symbol,
            tint: tint,
            isActive: shown > 0 && !isUnavailable,
            isUnavailable: isUnavailable,
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
                        flip()
                    }
                    .simultaneousGesture(drag(width: proxy.size.width), including: isUnavailable ? .none : .all)
            }
        }
        .allowsHitTesting(!isUnavailable)
        .animation(.snappy(duration: 0.2), value: shown)
        // Any live report replaces the optimistic value (web `useOptimisticState`).
        .onChange(of: percent) { interaction.pendingPercent = nil }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(Self.status(percent: shown, isUnavailable: isUnavailable))
        .accessibilityHint(isUnavailable ? "" : "Double-tap to turn \(shown > 0 ? "off" : "on"). Swipe up or down to adjust brightness.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { flip() }
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: send(interaction.adjust(by: Self.step, live: percent, isUnavailable: isUnavailable))
            case .decrement: send(interaction.adjust(by: -Self.step, live: percent, isUnavailable: isUnavailable))
            @unknown default: break
            }
        }
    }

    // MARK: - Intents

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

    private func drag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                interaction.dragChanged(translation: value.translation, x: value.location.x, width: width)
            }
            .onEnded { value in
                let intent = interaction.dragEnded(x: value.location.x, width: width, live: percent)
                if intent != nil { lastDragEnd = .now }
                send(intent)
            }
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

    /// The tile's status line and accessibility value: `Off`, `45%` or `Unavailable`.
    nonisolated static func status(percent: Int, isUnavailable: Bool) -> String {
        if isUnavailable { return "Unavailable" }
        return percent > 0 ? "\(percent)%" : "Off"
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

    private mutating func commit(_ value: Int, live: Int) -> Intent? {
        guard value != shown(live: live) else { return nil }
        pendingPercent = value
        return .brightness(value)
    }
}
