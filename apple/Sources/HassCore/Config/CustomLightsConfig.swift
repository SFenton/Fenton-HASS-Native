import Foundation

/// The Custom Lights page (web route `/at-a-glance/custom-lights`): the front yard's manual lighting mode and,
/// in Custom mode, each exterior light.
///
/// Source: `ha-sfenton-react-dash@9ac2a46:src/pages/CustomLightsPage.tsx` and
/// `src/components/hass/LightMoreInfoSheet.tsx`; copy from `src/i18n/locales/en/pages/customLights.json`.
public enum CustomLightsConfig {
    /// One exterior light.
    public struct Light: Hashable, Sendable, Identifiable {
        public var entityId: String
        public var title: String
        public var id: String { entityId }
    }

    /// An RGB color, 0...255 per channel (Home Assistant `rgb_color`).
    public struct RGB: Hashable, Sendable {
        public var red: Int
        public var green: Int
        public var blue: Int

        public init(_ red: Int, _ green: Int, _ blue: Int) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        /// Perceived brightness (web `rgbLuminance`).
        public var luminance: Double { 0.299 * Double(red) + 0.587 * Double(green) + 0.114 * Double(blue) }

        /// The light's `rgb_color`, when it reports three numbers.
        public init?(entity: EntityState?) {
            guard let values = entity?.attributes["rgb_color"]?.array?.compactMap(\.number), values.count == 3 else { return nil }
            self.init(Int(values[0]), Int(values[1]), Int(values[2]))
        }

        /// `[r, g, b]` for service data.
        public var json: JSONValue { .array([.number(Double(red)), .number(Double(green)), .number(Double(blue))]) }
    }

    // MARK: - Entities

    /// Turns manual control of the front yard lights on or off.
    public static let manualControlEntityId = "input_boolean.manually_control_front_yard_lights"
    /// The lighting mode (`Default`, `Custom`, `Seahawks`, `Valentine's Day`).
    public static let modeEntityId = "input_select.front_yard_custom_lights"
    /// Every front yard light (Reset All Lights, Apply to All Lights).
    public static let groupEntityId = "light.front_yard_lights"

    /// Section and picker titles (customLights.json).
    public static let frontYardTitle = "Front Yard"
    public static let lightingModeTitle = "Lighting Mode"

    /// The mode that shows each light.
    public static let customMode = "Custom"
    /// Used when the select reports no options (CustomLightsPage.tsx:144).
    public static let fallbackModes = ["Default", "Custom", "Seahawks", "Valentine's Day"]

    /// The eight lights, in web order (CustomLightsPage.tsx:21-30).
    public static let lights: [Light] = [
        Light(entityId: "light.front_door_exterior_left_light", title: "Left Door Light"),
        Light(entityId: "light.front_door_exterior_light_v2", title: "Right Door Light"),
        Light(entityId: "light.front_door_bollard_1", title: "Bollard 1"),
        Light(entityId: "light.front_door_bollard_2", title: "Bollard 2"),
        Light(entityId: "light.front_door_bollard_3", title: "Bollard 3"),
        Light(entityId: "light.front_door_bollard_4", title: "Bollard 4"),
        Light(entityId: "light.front_door_bollard_5", title: "Bollard 5"),
        Light(entityId: "light.front_door_bollard_6", title: "Bollard 6"),
    ]

    // MARK: - Modes

    /// The mode select's options, or the web's fallback list.
    public static func modes(_ select: EntityState?) -> [String] {
        let options = select?.attributes["options"]?.array?.compactMap(\.string) ?? []
        return options.isEmpty ? fallbackModes : options
    }

    /// The shown mode (web defaults to `Default`).
    public static func mode(_ select: EntityState?) -> String {
        select?.state ?? "Default"
    }

    /// Swatch colors for a mode, from the automations that drive it (CustomLightsPage.tsx:32-37): Seahawks
    /// green and blue, Valentine's Day red and pink, Custom the live light colors. `Default` has none.
    /// - Parameter custom: The live colors of the custom lights (Custom mode).
    public static func swatch(for mode: String, custom: [RGB]) -> [RGB] {
        switch mode {
        case "Seahawks": [RGB(0, 255, 0), RGB(0, 0, 255)]
        case "Valentine's Day": [RGB(255, 0, 0), RGB(255, 0, 234)]
        case customMode: customGradient(custom)
        default: []
        }
    }

    /// The Custom swatch: the lights' colors with duplicates removed, darkest to brightest (web `buildCustomGradient`).
    public static func customGradient(_ colors: [RGB]) -> [RGB] {
        var seen = Set<RGB>()
        let unique = colors.filter { seen.insert($0).inserted }
        // Stable for equal luminance, like the web's Array.sort.
        return unique.enumerated().sorted { lhs, rhs in
            lhs.element.luminance == rhs.element.luminance ? lhs.offset < rhs.offset : lhs.element.luminance < rhs.element.luminance
        }.map(\.element)
    }

    /// Whether the light reports a color mode the color controls can drive (LightMoreInfoSheet.tsx:19).
    public static func supportsColor(_ entity: EntityState?) -> Bool {
        let modes = entity?.attributes["supported_color_modes"]?.array?.compactMap(\.string) ?? []
        return modes.contains { ["hs", "rgb", "rgbw", "rgbww", "xy"].contains($0) }
    }

    // MARK: - Service calls

    /// Flips manual control. The web sends `homeassistant.toggle` to the helper; an input boolean is not a
    /// light, so Presence Lock does not apply, but the app still sends the explicit service for the shown state.
    public static func setManualControl(on: Bool) -> ServiceCall {
        ServiceCall("input_boolean", on ? "turn_on" : "turn_off", target: manualControlEntityId)
    }

    /// Picks a lighting mode.
    public static func selectMode(_ option: String) -> ServiceCall {
        ServiceCall("input_select", "select_option", target: modeEntityId, data: ["option": .string(option)])
    }

    /// Warm white (2000 K) at full brightness over one second: the default front yard scene.
    public static func reset(_ entityId: String = groupEntityId) -> ServiceCall {
        ServiceCall("light", "turn_on", target: entityId, data: [
            "color_temp_kelvin": .number(2000), "brightness": .number(255), "transition": .number(1),
        ])
    }

    /// Sets a light's color.
    public static func setColor(_ color: RGB, on entityId: String) -> ServiceCall {
        ServiceCall("light", "turn_on", target: entityId, data: ["rgb_color": color.json])
    }
}
