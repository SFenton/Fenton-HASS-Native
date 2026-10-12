import SwiftUI

/// The shared thermostat dial (pattern: `.agents/patterns/thermostat-dial.md`; web source
/// `ha-sfenton-react-dash@9ac2a46:src/pages/DashboardViewPage.tsx:4188` `ThermostatDial` over
/// `src/components/hass/CircularControlDial.tsx`).
///
/// Pure UI: callers pass a ``ThermostatDialConfiguration`` and receive setpoint commits; they map those to
/// `climate.set_temperature`. Dragging a handle shows the new setpoint at once and commits on release;
/// tapping the ring moves the nearest handle there. VoiceOver users adjust each handle by one step with
/// swipe up and down (HIG: Accessibility › VoiceOver, adjustable elements).
public struct ThermostatDial: View {
    // MARK: - Inputs

    /// How large the dial may grow (web `data-size`).
    public enum Size: Sendable {
        /// A page hero (web 316 px).
        case page
        /// Inside a sheet (web 300 px).
        case modal
        /// A small preview (web 250 px).
        case compact

        /// Largest ring diameter box, in points.
        public var maxSide: CGFloat {
            switch self {
            case .page: 316
            case .modal: 300
            case .compact: 250
            }
        }
    }

    public var configuration: ThermostatDialConfiguration
    public var size: Size
    /// Called with the new setpoints when a drag ends, the ring is tapped or VoiceOver adjusts a handle.
    public var onCommit: (ThermostatTargets) -> Void

    /// Creates a dial.
    public init(_ configuration: ThermostatDialConfiguration, size: Size = .page, onCommit: @escaping (ThermostatTargets) -> Void) {
        self.configuration = configuration
        self.size = size
        self.onCommit = onCommit
    }

    // MARK: - State

    @State private var editor = ThermostatDialEditor()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @ScaledMetric(relativeTo: .largeTitle) private var primarySize: CGFloat = 76

    /// Space outside the ring so a handle's 64 pt target never leaves the view (web modal dial gutter).
    static let gutter: CGFloat = 20

    private var geometry: ThermostatDialGeometry { configuration.geometry }
    private var displayed: ThermostatTargets? { editor.displayed(configuration) }
    private var activeHandle: ThermostatTargets.Handle? { editor.activeHandle }

    // MARK: - Body

    public var body: some View {
        GeometryReader { proxy in
            let side = Swift.max(Swift.min(proxy.size.width, proxy.size.height) - Self.gutter * 2, 0)
            ZStack {
                ring(side: side)
                readout(side: side)
                if configuration.acceptsInput, let displayed {
                    ForEach(displayed.handles, id: \.self) { handle in
                        handleView(handle, targets: displayed, side: side)
                    }
                }
            }
            .frame(width: side, height: side)
            .coordinateSpace(name: CoordinateSpaceKey.dial)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        // Square first, then cap: capped first, a wide column (unfolded Duo, iPad) proposed its full width
        // as the height and the ring floated in a tall empty box.
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: size.maxSide + Self.gutter * 2)
        .animation(reduceMotion || activeHandle != nil ? nil : .snappy(duration: 0.2), value: displayed)
        .sensoryFeedback(.selection, trigger: displayed) { _, _ in activeHandle != nil }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("thermostatDial")
    }

    // MARK: - Ring

    private func ring(side: CGFloat) -> some View {
        let lineWidth = side * 24 / 320
        return ZStack {
            arc(from: geometry.min, to: geometry.max)
                .stroke(trackColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            if let trails = configuration.valueStyle?.trails, !configuration.isUnavailable {
                ForEach(trails) { trail in
                    arc(from: trail.from, to: trail.to)
                        .stroke(Color(trail.tint), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                }
            }
            if case let .range(low, high)? = displayed, !configuration.isUnavailable {
                arc(from: geometry.min, to: low)
                    .stroke(ThermostatDialPalette.heat, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                arc(from: high, to: geometry.max)
                    .stroke(ThermostatDialPalette.cool, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            }
            if !configuration.isUnavailable, let current = configuration.current {
                Circle()
                    .fill(configuration.valueStyle.map { Color($0.tint) } ?? ThermostatDialPalette.color(for: configuration.thermalStatus))
                    // A dark rim in both appearances: with adaptive ink it turns white in dark mode and the
                    // marker reads as another handle (white disc, colored rim).
                    .overlay { Circle().strokeBorder(ThermostatDialPalette.markerRim, lineWidth: 3) }
                    .frame(width: 18, height: 18)
                    .position(geometry.point(for: current, side: side))
            }
        }
        .frame(width: side, height: side)
        .shadow(color: .black.opacity(0.18), radius: 14, y: 10)
        .opacity(configuration.isInactive ? 0.45 : 1)
        .saturation(configuration.isInactive ? 0 : 1)
        .contentShape(RingHitShape(radiusRatio: ThermostatDialGeometry.ringRadiusRatio, width: ThermostatDialGeometry.hitTarget))
        .gesture(SpatialTapGesture(coordinateSpace: .named(CoordinateSpaceKey.dial)).onEnded { tap in
            send(editor.tap(at: tap.location, side: side, in: configuration))
        }, including: configuration.acceptsInput ? .all : .none)
        .accessibilityHidden(true)
    }

    private func arc(from: Double, to: Double) -> RingArc {
        RingArc(from: geometry.fraction(of: from), to: geometry.fraction(of: to))
    }

    private var trackColor: Color {
        HassTokens.Ink.primary.opacity(contrast == .increased ? 0.38 : 0.16)
    }

    // MARK: - Readout

    private func readout(side: CGFloat) -> some View {
        // Read once here: the alignment guide's closure is Sendable and cannot touch main-actor state.
        let unitRaise = primarySize * 0.42
        return VStack(spacing: 4) {
            Text(configuration.actionText)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(HassTokens.Ink.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(configuration.primaryText(for: displayed))
                    .font(.system(size: primarySize, weight: .light))
                    .monospacedDigit()
                if let unit = configuration.primaryUnit {
                    // Raised with an alignment guide, not `baselineOffset`: the offset stretches the unit's
                    // frame to 2.5× its glyph and the accessibility audit then judges contrast on the
                    // empty part (iPad, 2026-10-10).
                    Text(unit)
                        .font(.system(size: primarySize * 0.32, weight: .bold))
                        .alignmentGuide(.firstTextBaseline) { $0[.firstTextBaseline] + unitRaise }
                }
            }
            .foregroundStyle(HassTokens.Ink.primary)
            if let caption = configuration.caption(for: displayed) {
                Group {
                    if configuration.valueStyle == nil {
                        Label(caption, systemImage: "thermometer.medium")
                    } else {
                        // Value-style captions ("Level 5 • 41% current") run longer than a temperature;
                        // two lines keep them whole in a small dial (unfolded iPhone Duo landscape).
                        Text(caption)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                }
                .font(.footnote.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(HassTokens.Ink.secondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.4)
        // Stay inside the ring; the inscribed square of the inner edge is ~0.6 of the side.
        .frame(maxWidth: side * 0.62, maxHeight: side * 0.62)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(configuration.readoutAccessibilityLabel)
        .accessibilityValue(configuration.readoutAccessibilityValue(for: displayed))
        .accessibilityIdentifier("thermostatDial.readout")
    }

    // MARK: - Handles

    private func handleView(_ handle: ThermostatTargets.Handle, targets: ThermostatTargets, side: CGFloat) -> some View {
        let value = targets.value(of: handle) ?? geometry.min
        let color = configuration.valueStyle.map { Color($0.tint) } ?? ThermostatDialPalette.color(for: handle, status: configuration.thermalStatus)
        let dragging = activeHandle == handle
        return Circle()
            .fill(.white)
            .overlay { Circle().strokeBorder(color, lineWidth: 4) }
            .frame(width: 24, height: 24)
            .shadow(color: .black.opacity(dragging ? 0.3 : 0.2), radius: dragging ? 12 : 6, y: dragging ? 10 : 4)
            .background {
                if dragging { Circle().fill(.white.opacity(0.12)).frame(width: 40, height: 40) }
            }
            .frame(width: ThermostatDialGeometry.hitTarget, height: ThermostatDialGeometry.hitTarget)
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named(CoordinateSpaceKey.dial))
                .onChanged { drag in
                    editor.drag(handle, to: drag.location, side: side, in: configuration)
                }
                .onEnded { drag in
                    send(editor.endDrag(handle, at: drag.location, side: side, in: configuration))
                })
            .accessibilityElement()
            .accessibilityLabel(configuration.accessibilityLabel(for: handle))
            .accessibilityValue(configuration.spokenValue(value))
            .accessibilityAdjustableAction { direction in
                send(editor.adjust(handle, increment: direction == .increment, in: configuration))
            }
            .accessibilityIdentifier("thermostatDial.handle.\(handle.rawValue)")
            .position(geometry.point(for: value, side: side))
    }

    // MARK: - Actions

    private func send(_ targets: ThermostatTargets?) {
        if let targets { onCommit(targets) }
    }
}

// MARK: - Supporting types

/// Thermostat colors from the web (`DashboardViewPage.tsx` `THERMOSTAT_*_COLOR`).
public enum ThermostatDialPalette {
    /// Heating and the heat-to handle (`#cd5401`).
    public static let heat = Color(red: 205 / 255, green: 84 / 255, blue: 1 / 255)
    /// Cooling and the cool-to handle (`#2c8e98`).
    public static let cool = Color(red: 44 / 255, green: 142 / 255, blue: 152 / 255)
    /// The current-temperature marker's rim: near-black in light and dark mode so it never looks like a handle.
    public static let markerRim = Color(white: 0.08)
    /// Idle (web: 78% white; here the adaptive secondary ink so it reads in light mode too).
    public static let neutral = HassTokens.Ink.secondary

    /// The color for a thermal status.
    public static func color(for status: ThermostatThermalStatus) -> Color {
        switch status {
        case .heat: heat
        case .cool: cool
        case .idle: neutral
        }
    }

    /// A handle's border: heat-to and cool-to are fixed; a single target follows the status.
    public static func color(for handle: ThermostatTargets.Handle, status: ThermostatThermalStatus) -> Color {
        switch handle {
        case .low: heat
        case .high: cool
        case .target: color(for: status)
        }
    }
}

extension Color {
    /// A dial tint as a SwiftUI color.
    public init(_ tint: DialTint) {
        self.init(.sRGB, red: tint.red / 255, green: tint.green / 255, blue: tint.blue / 255, opacity: tint.opacity)
    }
}

/// A stretch of the ring between two fractions (0 = minimum at 7:30, 1 = maximum at 4:30).
struct RingArc: Shape {
    var from: Double
    var to: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard to > from else { return path }
        let radius = Swift.min(rect.width, rect.height) * CGFloat(ThermostatDialGeometry.ringRadiusRatio)
        let start = ThermostatDialGeometry.startDegrees
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY), radius: radius,
            startAngle: .degrees(start + from * ThermostatDialGeometry.sweepDegrees),
            endAngle: .degrees(start + to * ThermostatDialGeometry.sweepDegrees),
            clockwise: false
        )
        return path
    }
}

/// The 64 pt band around the ring that accepts taps, so touches elsewhere fall through to a scroll view.
struct RingHitShape: Shape {
    var radiusRatio: Double
    var width: CGFloat

    func path(in rect: CGRect) -> Path {
        let side = Swift.min(rect.width, rect.height)
        let radius = side * CGFloat(radiusRatio)
        let circle = Path(ellipseIn: CGRect(x: rect.midX - radius, y: rect.midY - radius, width: radius * 2, height: radius * 2))
        return circle.strokedPath(StrokeStyle(lineWidth: width))
    }
}

private enum CoordinateSpaceKey {
    static let dial = "thermostatDial"
}
