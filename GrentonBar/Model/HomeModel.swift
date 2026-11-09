import Foundation
import GrentonKit

/// The lights and shutters of one interface and the connection behind them.
///
/// The connection starts when the menu first opens and then stays up until
/// the app quits: the CLUs push every change, and a started system costs a
/// ping per CLU every few seconds (library guidance for Mac apps, NOTES.md D1).
@Observable
@MainActor
final class HomeModel {
    let title: String
    let pages: [HomePage]
    private(set) var status: ConnectionStatus = .stopped
    /// The last command that failed, shown until the next command.
    private(set) var commandError: String?

    private let backend: Backend
    private var started = false
    @ObservationIgnored private var statusTask: Task<Void, Never>?

    enum Backend {
        case live(GrentonSystem)
        case demo(DemoDriver)
    }

    init(title: String, devices: [BoundDevice], physicalObjects: [PhysicalObject], backend: Backend) {
        self.title = title
        pages = HomeListBuilder.pages(devices: devices, physicalObjects: physicalObjects)
        self.backend = backend
        if case .demo(let driver) = backend {
            driver.attach(to: self)
        }
    }

    /// A model connected to the CLUs of `interface`. Nothing connects until the menu opens.
    static func live(interface: MobileInterfaceDTO) throws -> HomeModel {
        let system = try GrentonSystem(interface: interface, logger: .appLog)
        return HomeModel(title: interface.name, devices: system.devices,
                         physicalObjects: system.physicalObjects, backend: .live(system))
    }

    var isDemo: Bool {
        if case .demo = backend { true } else { false }
    }

    var demo: DemoDriver? {
        if case .demo(let driver) = backend { driver } else { nil }
    }

    // MARK: - Menu lifecycle

    /// Starts the connection the first time; later openings find it running.
    func menuOpened() {
        guard !started else { return }
        started = true
        switch backend {
        case .live(let system):
            status = .connecting
            statusTask = Task { [weak self] in
                // Subscribe before start(), so its state changes are not missed.
                let updates = await system.sessionStateUpdates()
                await system.start()
                await self?.refreshStatus()
                for await _ in updates {
                    guard let self else { return }
                    await self.refreshStatus()
                }
            }
        case .demo(let driver):
            driver.menuOpened()
        }
    }

    func menuClosed() {}

    /// Disconnects at once, before the app quits or another interface takes over.
    func shutdown() async {
        statusTask?.cancel()
        if case .live(let system) = backend {
            await system.stop()
        }
        status = .stopped
    }

    private func refreshStatus() async {
        guard case .live(let system) = backend else { return }
        status = ConnectionStatus.from(await system.diagnostics(), clus: system.clus)
    }

    /// Demo mode reports its simulated CLU states through here.
    func setDemoStatus(_ status: ConnectionStatus) {
        self.status = status
    }

    // MARK: - Commands

    func setLight(_ light: LightItem, on: Bool) {
        commandError = nil
        Task {
            do {
                if try await !light.setOn(on) {
                    commandError = "„\(light.name)” nie potwierdził zmiany — pokazuję stan zgłoszony przez CLU."
                }
            } catch {
                commandError = "Nie udało się przełączyć „\(light.name)”: \(Self.describe(error))"
            }
        }
    }

    func perform(_ command: CoverItem.Command, on cover: CoverItem) {
        commandError = nil
        // The demo CLU moves the shutter while the command waits for a report.
        demo?.echo(cover, command)
        Task {
            do {
                if try await !cover.perform(command) {
                    commandError = "„\(cover.name)” nie zgłosiła zmiany — pokazuję stan zgłoszony przez CLU."
                }
            } catch {
                commandError = "Nie udało się sterować roletą „\(cover.name)”: \(Self.describe(error))"
            }
        }
    }

    private static func describe(_ error: any Error) -> String {
        switch error as? SessionError {
        case .notConnected?, .connectionClosed?: "brak połączenia z CLU"
        case .timeout?: "CLU nie odpowiedział"
        default: error.localizedDescription
        }
    }
}

extension GrentonLogger {
    /// Library warnings in the unified log (Console.app, subsystem `com.osieckiadam.GrentonBar`).
    static let appLog = GrentonLogger { level, message in
        if level >= .warning { AppLog.grenton.warning("\(message, privacy: .public)") }
    }
}
