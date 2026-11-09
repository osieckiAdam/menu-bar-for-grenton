import AppKit
import GrentonKit
import SwiftUI

/// The window under the menu bar icon.
struct MenuView: View {
    let app: AppModel
    let openImport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
            Divider()
            MenuFooter(app: app, openImport: openImport)
        }
        .frame(width: 320)
        .background(WindowVisibilityObserver(onOpen: app.menuOpened, onClose: app.menuClosed))
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(app.home?.title ?? "Menu Bar for Grenton")
                .font(.headline)
                .lineLimit(1)
            if app.isDemo {
                Text("DEMO")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.orange.opacity(0.2), in: Capsule())
                    .foregroundStyle(.orange)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        switch app.phase {
        case .ready(let home):
            if home.pages.isEmpty {
                MessageView(symbol: "lightbulb.slash", title: "Brak urządzeń",
                            message: "Interfejs nie zawiera świateł (przełączników z ikoną lampy, ściemniaczy, świateł RGB) ani rolet.")
            } else {
                PageListView(home: home)
            }
        case .needsInterface:
            MessageView(symbol: "square.and.arrow.down", title: "Brak interfejsu",
                        message: "Zaimportuj interfejs mobilny z pliku albo pobierz go z Object Managera.",
                        action: ("Zaimportuj interfejs…", openImport))
        case .failed(let message):
            MessageView(symbol: "exclamationmark.triangle", title: "Błąd", message: message,
                        action: ("Zaimportuj interfejs…", openImport))
        }
    }
}

/// A centred placeholder with an optional button.
struct MessageView: View {
    let symbol: String
    let title: String
    let message: String
    var action: (String, () -> Void)?

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let action {
                Button(action.0, action: action.1)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
    }
}

#Preview("Demo") {
    MenuView(app: AppModel(isDemo: true), openImport: {})
}
