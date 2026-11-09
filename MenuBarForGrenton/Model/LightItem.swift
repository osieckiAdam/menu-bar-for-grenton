import Foundation
import GrentonKit
import GrentonSwiftUI

/// One light (a relay with a lamp icon, a dimmer or an RGB light) shown as a row.
///
/// Holds an `Observed` created once, so a view reading `isOn` re-renders
/// when the CLU reports a change. A switch is optimistic: it shows the
/// requested state at once and falls back to the CLU's state when the
/// command fails or the CLU does not confirm in time.
@Observable
@MainActor
final class LightItem: Identifiable {
    let id: String
    let name: String
    /// The entity behind the row; demo mode reads its descriptor to set raw values.
    let entity: BoundEntity
    /// The light as one on/off surface, observed; reading `value` subscribes a view.
    let observed: Observed<any SwitchableEntity>
    /// The state requested by the last command, until the CLU confirms it.
    private(set) var pendingOn: Bool?
    /// How long a requested state is shown without the CLU's confirmation.
    var confirmationTimeout: Duration = .seconds(3)
    @ObservationIgnored private var commandGeneration = 0

    /// Object Manager icon names that mean "not a light": sockets, power
    /// supplies, pumps, valves, heating, a door opener. Everything else is
    /// shown: installers pick icons by place (`sofa`, `tv`, `stairs`,
    /// `mirror`) as often as by device, so a lamp allowlist hides real
    /// lights (NOTES.md A6). Matched whole, or by prefix for numbered icons.
    static let nonLightIcons: Set<String> = [
        "power_socket", "socket", "power", "valve", "floor_heating", "ac", "door", "gate", "garage",
    ]
    static let nonLightIconPrefixes = ["vacuum_robot", "pump", "boiler", "heating"]

    /// A row for `entity`, or `nil` when it is not a light.
    init?(_ entity: BoundEntity) {
        guard let switchable = entity.switchable, Self.isLight(entity) else { return nil }
        self.entity = entity
        observed = Observed(switchable)
        id = entity.id
        name = entity.name
    }

    /// Dimmers and RGB lights are lights; a relay is one unless its icon says otherwise.
    static func isLight(_ entity: BoundEntity) -> Bool {
        guard case .toggle = entity else { return entity.switchable != nil }
        guard let icon = entity.icon?.lowercased() else { return true }
        if nonLightIcons.contains(icon) { return false }
        return !nonLightIconPrefixes.contains { icon.hasPrefix($0) }
    }

    /// The SF Symbol for the row, after the icon chosen in Object Manager.
    func symbol(on: Bool) -> String {
        let icon = entity.icon?.lowercased() ?? ""
        let base: String
        if icon.contains("chandelier") {
            base = "chandelier"
        } else if icon.contains("ceiling") || icon.contains("plafond") {
            base = "light.recessed"
        } else if icon.contains("led") || icon.contains("strip") {
            base = "light.strip.2"
        } else {
            base = "lightbulb"
        }
        return on ? base + ".fill" : base
    }

    /// Whether it is on, as the CLU last reported; `nil` until reported.
    var isOn: Bool? { observed.value.isOn }

    /// What the switch shows: the requested state while a command waits for confirmation, else ``isOn``.
    var displayedOn: Bool? { pendingOn ?? isOn }

    /// Sends the command and shows `on` until the CLU reports it.
    /// - Returns: Whether the CLU confirmed within ``confirmationTimeout``.
    /// - Throws: What the command throws; the switch then shows the CLU's state again.
    @discardableResult
    func setOn(_ on: Bool) async throws -> Bool {
        commandGeneration += 1
        let generation = commandGeneration
        let timeout = confirmationTimeout
        pendingOn = on
        // A newer command owns the pending state; this one must not clear it.
        defer { if generation == commandGeneration { pendingOn = nil } }

        // Subscribe before sending, so a quick report is not missed (NOTES.md A7).
        let light = observed.value
        let updates = light.updates()
        try await light.setOn(on)
        if isOn == on { return true }
        return await Confirmation.first(of: updates, where: { [weak self] in self?.isOn == on }, within: timeout)
    }
}

/// Waits for an entity's report after a command (NOTES.md A7).
enum Confirmation {
    /// `true` when `updates` fires and `condition` holds before `timeout` runs out.
    @MainActor
    static func first(of updates: AsyncStream<Void>, where condition: @escaping @MainActor () -> Bool,
                      within timeout: Duration) async -> Bool {
        let listener = Task { () -> Bool in
            for await _ in updates where condition() { return true }
            return false
        }
        // Cancelling the listener ends its stream, so it returns false.
        let deadline = Task {
            try? await Task.sleep(for: timeout)
            listener.cancel()
        }
        let confirmed = await listener.value
        deadline.cancel()
        return confirmed
    }
}
