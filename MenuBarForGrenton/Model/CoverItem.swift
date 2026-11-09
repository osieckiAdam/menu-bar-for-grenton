import Foundation
import GrentonKit
import GrentonSwiftUI

/// One roller shutter (a `ROLLER_SHUTTER_V3` widget) shown as a row.
///
/// A command is optimistic: the row says what was asked ("otwieram…")
/// until the CLU reports any change — a new motion state, position or
/// tilt — and falls back to the CLU's state when the command fails or
/// nothing is reported in time. A shutter travels for tens of seconds, so
/// the first report, not the target position, is the confirmation.
@Observable
@MainActor
final class CoverItem: Identifiable {
    /// What the row can ask of the shutter.
    enum Command: Equatable {
        case open
        case close
        case stop
        /// Slat tilt from 0 (closed) to 100 (open).
        case tilt(Int)
    }

    let id: String
    let name: String
    /// The entity behind the row; demo mode reads its descriptor to set raw values.
    let entity: BoundEntity
    let observed: Observed<CoverEntity>
    /// The command sent last, until the CLU reports a change.
    private(set) var pending: Command?
    /// How long a sent command is shown without any report from the CLU.
    var confirmationTimeout: Duration = .seconds(3)
    @ObservationIgnored private var commandGeneration = 0

    /// A row for `entity`, or `nil` when it is not a shutter.
    init?(_ entity: BoundEntity) {
        guard case .cover(let cover) = entity else { return nil }
        self.entity = entity
        observed = Observed(cover)
        id = entity.id
        name = entity.name
    }

    /// The shutter, current as of the last report; reading it subscribes a view.
    var cover: CoverEntity { observed.value }

    /// Position from 0 (closed) to 100 (open); `nil` until reported.
    var position: Int? { cover.position }
    var motion: CoverMotion { cover.motion }
    /// Slat tilt from 0 (closed) to 100 (open); `nil` until reported or without slats.
    var tilt: Int? { cover.tilt }
    var supportsTilt: Bool { cover.supportsTilt }
    var supportsStop: Bool { cover.supportsStop }

    /// The tilt the slider shows: the requested one while it waits for confirmation, else ``tilt``.
    var displayedTilt: Int? {
        if case .tilt(let value) = pending { value } else { tilt }
    }

    /// Whether the row should look closed.
    var looksClosed: Bool {
        switch pending {
        case .close?: return true
        case .open?: return false
        default: return position == 0
        }
    }

    /// One line about the shutter: what was asked, what it is doing, or where it is.
    var stateText: String {
        switch pending {
        case .open?: return "otwieram…"
        case .close?: return "zamykam…"
        case .stop?: return "zatrzymuję…"
        default: break
        }
        switch motion {
        case .opening: return "otwiera się…"
        case .closing: return "zamyka się…"
        default: break
        }
        guard let position else { return "–" }
        switch position {
        case 0: return "zamknięta"
        case 100: return "otwarta"
        default: return "\(position) %"
        }
    }

    /// Sends the command and shows it until the CLU reports a change.
    /// - Returns: Whether the CLU reported within ``confirmationTimeout``; also `true` when the shutter was already there.
    /// - Throws: What the command throws; the row then shows the CLU's state again.
    @discardableResult
    func perform(_ command: Command) async throws -> Bool {
        commandGeneration += 1
        let generation = commandGeneration
        let timeout = confirmationTimeout
        pending = command
        defer { if generation == commandGeneration { pending = nil } }

        let cover = observed.value
        // Subscribe before sending, so a quick report is not missed (NOTES.md A7).
        let updates = cover.updates()
        let satisfiedAlready = isSatisfied(command)
        try await send(command, to: cover)
        if satisfiedAlready { return true }
        return await Confirmation.first(of: updates, where: { true }, within: timeout)
    }

    /// A command the shutter has nothing to do for; the CLU may well report nothing.
    private func isSatisfied(_ command: Command) -> Bool {
        switch command {
        case .open: position == 100 && motion == .idle
        case .close: position == 0 && motion == .idle
        case .stop: motion == .idle || !supportsStop
        case .tilt(let value): tilt == value || !supportsTilt
        }
    }

    private func send(_ command: Command, to cover: CoverEntity) async throws {
        switch command {
        case .open: try await cover.open()
        case .close: try await cover.close()
        case .stop: try await cover.stop()
        case .tilt(let value): try await cover.setTilt(value)
        }
    }
}
