import Foundation
import GrentonKit

/// What the status bar at the bottom of the menu says about the CLUs.
enum ConnectionStatus: Equatable {
    /// Not connected: the menu was closed long enough.
    case stopped
    /// `start()` is running, or every CLU is still subscribing.
    case connecting
    /// Every CLU answers.
    case connected(cluCount: Int)
    /// Some CLUs answer, the named ones do not.
    case partial(down: [String], cluCount: Int)
    /// No CLU answers. `neverAnswered`: not once since the start, which on a
    /// Mac usually means Local Network access is missing.
    case offline(neverAnswered: Bool)

    /// The status for one snapshot of `GrentonSystem.diagnostics()`.
    static func from(_ diagnostics: [String: SessionDiagnostics], clus: [Clu]) -> ConnectionStatus {
        let states = diagnostics.mapValues(\.state)
        let names = Dictionary(clus.map { ($0.id, $0.name.isEmpty ? $0.id : $0.name) }, uniquingKeysWith: { first, _ in first })
        guard !states.isEmpty else { return .stopped }

        let ready = states.filter { $0.value == .ready }
        let degraded = states.filter { $0.value == .degraded }.keys.sorted()
        if ready.count == states.count { return .connected(cluCount: states.count) }
        if ready.isEmpty, degraded.count == states.count {
            return .offline(neverAnswered: diagnostics.values.allSatisfy { $0.sinceLastReply == nil })
        }
        if !degraded.isEmpty { return .partial(down: degraded.map { names[$0] ?? $0 }, cluCount: states.count) }
        if states.values.contains(.starting) { return .connecting }
        return .stopped
    }

    var isProblem: Bool {
        switch self {
        case .partial, .offline: true
        case .stopped, .connecting, .connected: false
        }
    }
}
