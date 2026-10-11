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
    public static let step = 10
    /// Optimistic values give way to live state after this long even if the server never echoes them.
    static let pendingTimeout: Duration = .seconds(4)

    @State private var dragPercent: Double?
    @State private var pendingPercent: Int?
    @State private var dragAxis: DragAxis?
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
        let shown = shownPercent
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
        .onChange(of: percent) { pendingPercent = nil }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(Self.status(percent: shown, isUnavailable: isUnavailable))
        .accessibilityHint(isUnavailable ? "" : "Double-tap to turn \(shown > 0 ? "off" : "on"). Swipe up or down to adjust brightness.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { flip() }
        .accessibilityAdjustableAction { direction in
            guard !isUnavailable else { return }
            switch direction {
            case .increment: commit(Self.stepped(shown, by: Self.step))
            case .decrement: commit(Self.stepped(shown, by: -Self.step))
            @unknown default: break
            }
        }
    }

    // MARK: - State

    private var shownPercent: Int {
        if let dragPercent { return Int(dragPercent.rounded()) }
        return pendingPercent ?? percent
    }

    private func flip() {
        guard !isUnavailable else { return }
        let on = shownPercent == 0
        // Optimistic: off shows 0; on shows full until Home Assistant reports the restored level.
        hold(on ? 100 : 0)
        onPower(on)
    }

    private func commit(_ value: Int) {
        guard value != shownPercent else { return }
        hold(value)
        onBrightness(value)
    }

    /// Shows `value` until the live percent catches up or ``pendingTimeout`` passes.
    private func hold(_ value: Int) {
        pendingPercent = value
        pendingTask?.cancel()
        pendingTask = Task { @MainActor in
            try? await Task.sleep(for: Self.pendingTimeout)
            guard !Task.isCancelled else { return }
            pendingPercent = nil
        }
    }

    private func drag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                if dragAxis == nil {
                    dragAxis = abs(value.translation.width) >= abs(value.translation.height) ? .horizontal : .vertical
                }
                guard dragAxis == .horizontal else { return }
                dragPercent = Self.percent(atX: value.location.x, width: width)
            }
            .onEnded { value in
                defer { dragAxis = nil }
                guard dragAxis == .horizontal, dragPercent != nil else { return }
                dragPercent = nil
                lastDragEnd = .now
                commit(Int(Self.percent(atX: value.location.x, width: width).rounded()))
            }
    }

    // MARK: - Pure helpers

    enum DragAxis { case horizontal, vertical }

    /// Percent for a touch at `x` across a tile `width` wide, clamped to 0...100.
    static func percent(atX x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return min(100, max(0, Double(x / width) * 100))
    }

    /// `value` moved by `delta`, clamped to 0...100.
    static func stepped(_ value: Int, by delta: Int) -> Int {
        min(100, max(0, value + delta))
    }

    /// The tile's status line and accessibility value: `Off`, `45%` or `Unavailable`.
    static func status(percent: Int, isUnavailable: Bool) -> String {
        if isUnavailable { return "Unavailable" }
        return percent > 0 ? "\(percent)%" : "Off"
    }
}
