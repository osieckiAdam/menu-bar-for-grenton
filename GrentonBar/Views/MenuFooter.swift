import AppKit
import GrentonKit
import SwiftUI

/// The bottom of the menu: CLU status, the last error, and the actions menu.
struct MenuFooter: View {
    let app: AppModel
    let openImport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                if let home = app.home {
                    StatusLine(status: home.status)
                }
                Spacer()
                actionsMenu
            }
            if let home = app.home {
                if let error = home.commandError {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var actionsMenu: some View {
        Menu {
            Button("Zmień interfejs…", action: openImport)
            if let demo = app.home?.demo {
                Divider()
                Section("Demo") {
                    Button("Przełącz losowe światło (jak z włącznika)") { demo.flipRandomLight() }
                    ForEach(demo.simulation.clus, id: \.id) { clu in
                        Button(demo.offlineClus.contains(clu.id) ? "Przywróć \(clu.name)" : "Symuluj awarię: \(clu.name)") {
                            demo.toggleOffline(clu)
                        }
                    }
                }
            }
            Divider()
            Button("Zakończ GrentonBar") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

/// A coloured dot and one sentence about the CLUs.
struct StatusLine: View {
    let status: ConnectionStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if status == .connecting {
                    ProgressView().controlSize(.mini)
                } else {
                    Circle().fill(color).frame(width: 7, height: 7)
                }
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if case .offline(neverAnswered: true) = status {
                Button("Sprawdź dostęp do sieci lokalnej…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.link)
                .font(.caption)
            }
        }
    }

    private var color: Color {
        switch status {
        case .connected: .green
        case .partial: .orange
        case .offline: .red
        case .stopped, .connecting: .secondary
        }
    }

    private var text: String {
        switch status {
        case .stopped: "Rozłączono"
        case .connecting: "Łączenie z CLU…"
        case .connected(let count): count == 1 ? "Połączono z CLU" : "Połączono · \(count) CLU"
        case .partial(let down, let count): "Nie odpowiada: \(down.joined(separator: ", ")) (z \(count) CLU)"
        case .offline(let never): never ? "Żaden CLU nie odpowiedział" : "CLU przestały odpowiadać — ponawiam"
        }
    }
}

#Preview("Statusy") {
    VStack(alignment: .leading, spacing: 10) {
        StatusLine(status: .connecting)
        StatusLine(status: .connected(cluCount: 2))
        StatusLine(status: .partial(down: ["CLU Demo Góra"], cluCount: 2))
        StatusLine(status: .offline(neverAnswered: true))
        StatusLine(status: .offline(neverAnswered: false))
        StatusLine(status: .stopped)
    }
    .padding()
    .frame(width: 320)
}
