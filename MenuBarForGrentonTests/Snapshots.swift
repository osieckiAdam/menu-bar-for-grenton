import AppKit
import SwiftUI
import Testing
@testable import MenuBarForGrenton

/// Renders the menu and the import window to PNG for a visual check without
/// clicking the menu bar. Runs only when asked:
/// `TEST_RUNNER_SNAPSHOT_DIR=/some/dir xcodebuild test -only-testing:MenuBarForGrentonTests/Snapshots`
@MainActor
struct Snapshots {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] != nil))
    func render() async throws {
        let app = AppModel(isDemo: true)
        app.menuOpened()
        try await Task.sleep(for: .milliseconds(900))
        try await save(MenuView(app: app, openImport: {}), "menu-demo")
        // A room with lights and shutters open; the user's own choice comes back afterwards.
        let defaults = UserDefaults.standard
        let expanded = defaults.string(forKey: "expandedPages")
        defaults.set("Pokój dzienny (demo)", forKey: "expandedPages")
        try await save(MenuView(app: app, openImport: {}), "menu-room")
        defaults.set(expanded, forKey: "expandedPages")
        app.home?.demo?.toggleOffline(app.home!.demo!.simulation.clus[1])
        try await Task.sleep(for: .milliseconds(100))
        try await save(MenuView(app: app, openImport: {}), "menu-degraded")
        try await save(MenuView(app: AppModel(isDemo: false), openImport: {}), "menu-empty")
        let importModel = ImportModel(app: app)
        importModel.source = .objectManager
        try await save(ImportView(model: importModel, close: {}), "import-om")
    }

    private func save(_ view: some View, _ name: String) async throws {
        let host = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
        host.appearance = NSAppearance(named: .aqua)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 320, height: 800), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        for _ in 0..<5 {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(50))
            window.setContentSize(host.fittingSize)
        }
        host.layoutSubtreeIfNeeded()
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let dir = try #require(ProcessInfo.processInfo.environment["SNAPSHOT_DIR"])
        try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }
}
