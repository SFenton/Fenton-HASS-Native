import HassCore
import HassDesign
import SwiftUI

// MARK: - Entity mapping

extension ThermostatDialConfiguration {
    /// Maps a `climate` entity the way the web's `ThermostatDial` reads it
    /// (`ha-sfenton-react-dash@9ac2a46:src/pages/DashboardViewPage.tsx:4188`).
    ///
    /// - Range mode when both `target_temp_low` and `target_temp_high` are numbers, else one `temperature` handle.
    /// - Range defaults: `min_temp` 45, `max_temp` 95, `target_temp_step` 0.5.
    /// - The action is `hvac_action`, falling back to the state.
    /// - Parameters:
    ///   - entity: The climate entity, or `nil` if the server doesn't know it (shown unavailable).
    ///   - title: Name used in accessibility labels.
    public init(entity: EntityState?, title: String) {
        let attributes = entity?.attributes ?? [:]
        let low = attributes["target_temp_low"]?.number
        let high = attributes["target_temp_high"]?.number
        let targets: ThermostatTargets? = if let low, let high {
            .range(low: low, high: high)
        } else {
            attributes["temperature"]?.number.map { .single($0) }
        }
        self.init(
            title: title,
            min: attributes["min_temp"]?.number ?? 45,
            max: attributes["max_temp"]?.number ?? 95,
            step: attributes["target_temp_step"]?.number ?? 0.5,
            current: attributes["current_temperature"]?.number,
            targets: targets,
            action: attributes["hvac_action"]?.string ?? entity?.state ?? "idle",
            unit: attributes["temperature_unit"]?.string ?? attributes["unit_of_measurement"]?.string ?? "°F",
            isUnavailable: entity?.isUnavailable ?? true,
            isOff: entity?.state == "off"
        )
    }
}

extension ThermostatTargets {
    /// `climate.set_temperature` service data for `entityIds`.
    public func setTemperatureData(entityIds: [String]) -> [String: any Sendable] {
        var data: [String: any Sendable] = serviceData
        data["entity_id"] = entityIds.count == 1 ? entityIds[0] : entityIds
        return data
    }
}

// MARK: - Bound dial

/// A ``ThermostatDial`` bound to one climate entity in the ``EntityStore``. Commits call
/// `climate.set_temperature` on that entity, or on `commitEntityIds` when set (the web sends the global
/// virtual thermostat's range to every room thermostat).
public struct ClimateThermostatDial: View {
    public var entityId: String
    public var title: String
    public var size: ThermostatDial.Size
    public var commitEntityIds: ((ThermostatTargets) -> [String])?
    /// Shown instead of the entity's `hvac_action` (the Whole Home dial always shows the global thermostat's).
    public var action: String?
    /// Where commits go; `nil` uses the environment's ``HassConnection``.
    public var caller: (any HassServiceCalling)?

    @Environment(EntityStore.self) private var store
    @Environment(HassConnection.self) private var connection: HassConnection?
    /// The last commit failed; cleared by the next one.
    @State private var failed = false

    /// Creates a bound dial.
    public init(
        entityId: String, title: String, size: ThermostatDial.Size = .page, action: String? = nil,
        caller: (any HassServiceCalling)? = nil, commitEntityIds: ((ThermostatTargets) -> [String])? = nil
    ) {
        self.entityId = entityId
        self.title = title
        self.size = size
        self.action = action
        self.caller = caller
        self.commitEntityIds = commitEntityIds
    }

    public var body: some View {
        var configuration = ThermostatDialConfiguration(entity: store.entity(entityId).state, title: title)
        if let action { configuration.action = action }
        return VStack(spacing: HassTokens.Spacing.s) {
            ThermostatDial(configuration, size: size) { commit($0) }
            if failed {
                Label(Self.failureMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(HassTokens.Ink.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("thermostatDial.failure")
            }
        }
    }

    /// Shown under the dial when Home Assistant rejects a commit. The handles follow the entity back to its
    /// unchanged targets, so the message says why they moved.
    static let failureMessage = "Home Assistant didn't change the temperature. Try again."

    /// Sends a commit to ``caller``, else the environment's connection. A failure shows ``failureMessage`` under
    /// the dial and is announced to VoiceOver.
    @discardableResult
    func commit(_ targets: ThermostatTargets) -> Task<Void, Never>? {
        let data = setTemperatureData(for: targets)
        guard let target: any HassServiceCalling = caller ?? connection else { return nil }
        failed = false
        let failed = $failed
        return Task {
            do {
                try await target.callService("climate", "set_temperature", data: data)
            } catch {
                failed.wrappedValue = true
                AccessibilityNotification.Announcement(Self.failureMessage).post()
            }
        }
    }

    /// The `climate.set_temperature` data a commit sends: this entity, or `commitEntityIds` when set.
    func setTemperatureData(for targets: ThermostatTargets) -> [String: any Sendable] {
        targets.setTemperatureData(entityIds: commitEntityIds?(targets) ?? [entityId])
    }
}
