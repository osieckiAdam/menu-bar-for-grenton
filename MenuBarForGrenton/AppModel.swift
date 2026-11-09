import Foundation
import GrentonKit

/// The app's state: which interface it shows, or that it needs one.
@Observable
@MainActor
final class AppModel {
    enum Phase {
        case needsInterface
        case ready(HomeModel)
        case failed(String)
    }

    private(set) var phase: Phase = .needsInterface
    /// Whether the menu shows the bundled demo interface instead of the saved one.
    let isDemo: Bool

    @ObservationIgnored let store: InterfaceStore?
    @ObservationIgnored private var menuOpen = false

    init(isDemo: Bool = UserDefaults.standard.bool(forKey: DemoDriver.defaultsKey)) {
        self.isDemo = isDemo
        do {
            store = try InterfaceStore()
        } catch {
            store = nil
            phase = .failed("Nie można otworzyć magazynu interfejsu: \(error.localizedDescription)")
            return
        }
        reload()
    }

    var home: HomeModel? {
        if case .ready(let home) = phase { home } else { nil }
    }

    /// Loads the demo interface or the saved one.
    func reload() {
        do {
            if isDemo {
                phase = .ready(try DemoDriver.makeHome())
            } else if let interface = try store?.interface() {
                phase = .ready(try HomeModel.live(interface: interface))
            } else {
                Task { await replace(with: .needsInterface) }
            }
        } catch {
            phase = .failed("Nie można wczytać interfejsu: \(error.localizedDescription)")
        }
    }

    /// Saves an interface archive (downloaded from Object Manager or picked as .zip) and switches to it.
    func useArchive(_ archive: Data) async throws {
        guard let store else { throw InterfaceStoreError.noBundleIdentifier }
        try store.save(archive)
        try await showSaved()
    }

    /// Saves a project file (.omp) with the chosen interface and switches to it.
    func useProject(_ project: Data, interfaceId: String?) async throws {
        guard let store else { throw InterfaceStoreError.noBundleIdentifier }
        try store.save(project: project, interfaceId: interfaceId)
        try await showSaved()
    }

    /// Whether there may be a saved interface (and with it the CLU key) to remove.
    var canRemoveInterface: Bool {
        if isDemo || store == nil { return false }
        if case .needsInterface = phase { return false }
        return true
    }

    /// Disconnects and deletes the saved interface, key included.
    func removeInterface() async throws {
        try store?.remove()
        await replace(with: .needsInterface)
    }

    func menuOpened() {
        menuOpen = true
        home?.menuOpened()
    }

    func menuClosed() {
        menuOpen = false
        home?.menuClosed()
    }

    func shutdown() async {
        await home?.shutdown()
    }

    private func showSaved() async throws {
        guard !isDemo, let interface = try store?.interface() else { return }
        await replace(with: .ready(try HomeModel.live(interface: interface)))
    }

    /// Stops the current connection before showing another interface.
    private func replace(with phase: Phase) async {
        let previous = home
        self.phase = phase
        await previous?.shutdown()
        if menuOpen { home?.menuOpened() }
    }
}
