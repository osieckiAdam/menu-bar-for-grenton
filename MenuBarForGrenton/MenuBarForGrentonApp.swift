import AppKit
import SwiftUI

@main
struct MenuBarForGrentonApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuView(app: delegate.app, openImport: delegate.showImport)
        } label: {
            MenuBarIcon(app: delegate.app)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let app = AppModel()
    private lazy var importWindow = ImportWindowController(model: ImportModel(app: app))

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Unit tests run inside the app; they need no window.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        if case .needsInterface = app.phase { showImport() }
    }

    func showImport() {
        importWindow.show()
    }

    /// Disconnects before quitting, so every CLU stops pushing at once.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task {
            await app.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

/// The icon in the menu bar: a crossed-out bulb when something needs attention.
struct MenuBarIcon: View {
    let app: AppModel

    var body: some View {
        // A fixed size: the two symbols differ in width, and a status item
        // whose label changes width can end up drawn under its neighbour
        // (MenuBarExtra does not always relayout the menu bar).
        Image(systemName: needsAttention ? "lightbulb.slash" : "lightbulb")
            .frame(width: 22, height: 22)
            .accessibilityLabel("Menu Bar for Grenton")
    }

    private var needsAttention: Bool {
        switch app.phase {
        case .ready(let home): home.status.isProblem
        case .needsInterface, .failed: true
        }
    }
}
