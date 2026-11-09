import Foundation
import GrentonKit
import GrentonSimulation

/// Demo mode: the bundled synthetic interface on `SimulatedGrentonSystem`,
/// standing in for the CLUs so the menu can be tried without a house.
///
/// The simulation echoes on/off commands as a CLU would report them
/// (`echoesSwitches`, NOTES.md A5); shutters it leaves alone, so the
/// driver plays their CLU and moves them step by step. It also adds what
/// a demo needs besides: a random starting state, a light flipped "from
/// the wall switch", and a CLU taken offline.
@Observable
@MainActor
final class DemoDriver {
    /// Launch argument that turns demo mode on: `-DemoMode YES` (set in the Debug scheme).
    static let defaultsKey = "DemoMode"

    let simulation: SimulatedGrentonSystem
    private(set) var offlineClus: Set<String> = []
    @ObservationIgnored private weak var home: HomeModel?
    /// The simulated travel of each shutter, by row id.
    @ObservationIgnored private var travels: [String: Task<Void, Never>] = [:]
    /// How long the demo CLU takes to answer, and between position steps.
    static let reportDelay: Duration = .milliseconds(250)
    static let stepInterval: Duration = .milliseconds(300)

    init(simulation: SimulatedGrentonSystem) {
        self.simulation = simulation
    }

    /// The model for the bundled demo interface, with a random half of the lights on and the shutters at rest.
    static func makeHome() throws -> HomeModel {
        let interface = try demoInterface()
        let simulation = SimulatedGrentonSystem(interface: interface, echoesSwitches: true)
        let driver = DemoDriver(simulation: simulation)
        let home = HomeModel(title: interface.name, devices: simulation.devices,
                             physicalObjects: simulation.physicalObjects, backend: .demo(driver))
        for light in home.pages.flatMap(\.lights) {
            driver.report(light, on: Bool.random())
        }
        for cover in home.pages.flatMap(\.covers) {
            driver.report(cover, position: [0, 40, 100].randomElement()!, tilt: Int.random(in: 0...10) * 10)
        }
        return home
    }

    static func demoInterface() throws -> MobileInterfaceDTO {
        guard let url = Bundle.main.url(forResource: "demo-interface", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(MobileInterfaceDTO.self, from: Data(contentsOf: url))
    }

    func attach(to home: HomeModel) {
        self.home = home
    }

    func menuOpened() {
        // A real start() takes a moment; show it.
        home?.setDemoStatus(.connecting)
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            publishStatus()
        }
    }

    /// Flips a random light, as someone pressing a wall switch.
    func flipRandomLight() {
        guard let light = home?.pages.flatMap(\.lights).randomElement() else { return }
        report(light, on: !(light.isOn ?? false))
    }

    func toggleOffline(_ clu: Clu) {
        if offlineClus.remove(clu.id) == nil { offlineClus.insert(clu.id) }
        publishStatus()
    }

    private func publishStatus() {
        let now = Date()
        let diagnostics = Dictionary(uniqueKeysWithValues: simulation.clus.map { clu in
            let offline = offlineClus.contains(clu.id)
            return (clu.id, SessionDiagnostics(
                state: offline ? .degraded : .ready, sampledAt: now,
                sinceLastReply: offline ? .seconds(20) : .milliseconds(300), sinceLastReport: nil,
                lastPingRoundTrip: .milliseconds(4), requestedKeyCount: 0, recoveryPending: offline,
                consecutivePingTimeouts: offline ? 3 : 0))
        })
        home?.setDemoStatus(ConnectionStatus.from(diagnostics, clus: simulation.clus))
    }

    /// Moves a shutter the way its CLU would report it: the motion state
    /// first, then the position in steps, then idle. A new command on the
    /// same shutter interrupts the travel.
    func echo(_ cover: CoverItem, _ command: CoverItem.Command) {
        guard case .cover(let entity) = cover.entity else { return }
        let descriptor = entity.descriptor
        travels[cover.id]?.cancel()
        travels[cover.id] = Task { [simulation] in
            try? await Task.sleep(for: Self.reportDelay)
            guard !Task.isCancelled else { return }
            switch command {
            case .stop:
                simulation.set(descriptor.motionState, to: .int(0))
            case .tilt(let value):
                guard let tilt = descriptor.tilt else { return }
                simulation.set(tilt.position, to: .int(Self.deviceTilt(value)))
            case .open, .close:
                let target = command == .open ? 100 : 0
                var position = entity.position ?? (100 - target)
                guard position != target else { return }
                simulation.set(descriptor.motionState, to: .int(target == 100 ? 1 : 2))
                while position != target {
                    try? await Task.sleep(for: Self.stepInterval)
                    guard !Task.isCancelled else { return }
                    position = target == 100 ? min(position + 10, 100) : max(position - 10, 0)
                    simulation.set(descriptor.position, to: .int(Int64(position)))
                }
                simulation.set(descriptor.motionState, to: .int(0))
            }
        }
    }

    /// Sets a shutter's raw values as its CLU would report them: at rest, at `position`, slats at `tilt`.
    private func report(_ cover: CoverItem, position: Int, tilt: Int) {
        guard case .cover(let entity) = cover.entity else { return }
        simulation.set(entity.descriptor.motionState, to: .int(0))
        simulation.set(entity.descriptor.position, to: .int(Int64(position)))
        if let slats = entity.descriptor.tilt {
            simulation.set(slats.position, to: .int(Self.deviceTilt(tilt)))
        }
    }

    /// The device's lamel value for a canonical tilt: 0…90 on an inverted scale (spec §6.3.8).
    private static func deviceTilt(_ tilt: Int) -> Int64 {
        Int64(90 - Double(tilt) * 0.9)
    }

    /// Sets a light's raw value as its CLU would report it.
    private func report(_ light: LightItem, on: Bool) {
        switch light.entity {
        case .toggle(let toggle):
            simulation.set(toggle.descriptor.state, to: .string(on ? "ON" : "OFF"))
        case .dimmableLight(let dimmer):
            let descriptor = dimmer.descriptor
            simulation.set(descriptor.state, to: .double(on ? descriptor.max : descriptor.min))
        case .hsbLight(let led):
            simulation.set(led.descriptor.powerState, to: .int(on ? 1 : 0))
        default:
            break
        }
    }
}
