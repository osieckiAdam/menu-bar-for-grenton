import AppKit
import GrentonKit
import SwiftUI

/// Shows the import window. A regular window rather than part of the menu:
/// the menu closes as soon as a file panel takes focus.
@MainActor
final class ImportWindowController {
    private let model: ImportModel
    private var window: NSWindow?

    init(model: ImportModel) {
        self.model = model
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(
                rootView: ImportView(model: model, close: { [weak self] in self?.window?.close() })))
            window.title = "Interfejs Grenton"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        if !model.isWorking { model.reset() }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

struct ImportView: View {
    @Bindable var model: ImportModel
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Źródło", selection: $model.source) {
                Text("Plik").tag(ImportModel.Source.file)
                Text("Object Manager").tag(ImportModel.Source.objectManager)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: .infinity)
            .disabled(model.isWorking)

            switch model.source {
            case .file: fileSource
            case .objectManager: objectManagerSource
            }

            StepView(model: model, close: close)

            Text("Interfejs zawiera klucz szyfrowania Twoich CLU. GrentonBar przechowuje go wyłącznie w swoim katalogu w Application Support.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 420)
    }

    private var fileSource: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Archiwum interfejsu (.zip) zapisane z Object Managera albo plik projektu (.omp).")
                .fixedSize(horizontal: false, vertical: true)
            Button("Wybierz plik…", action: model.pickFile)
                .disabled(model.isWorking)
        }
    }

    private var objectManagerSource: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("W Object Managerze wybierz interfejs mobilny i kliknij „Wyślij do urządzeń mobilnych”. Okno pokaże adres komputera i PIN — zostaw je otwarte na czas pobierania.")
                .fixedSize(horizontal: false, vertical: true)
            Form {
                TextField("Adres", text: $model.host, prompt: Text("192.168.1.50"))
                TextField("PIN", text: $model.pin, prompt: Text("123 456"))
            }
            .disabled(model.isWorking)
            HStack {
                Spacer()
                Button("Pobierz", action: model.download)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canDownload)
            }
        }
    }
}

/// Progress, the interface choice for a multi-interface project, and the result.
private struct StepView: View {
    @Bindable var model: ImportModel
    let close: () -> Void

    var body: some View {
        switch model.step {
        case .idle:
            EmptyView()
        case .working(let message):
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(message)
            }
        case .choosingInterface(_, let interfaces):
            VStack(alignment: .leading, spacing: 8) {
                Text("Projekt zawiera kilka interfejsów mobilnych. Wybierz jeden:")
                Picker("Interfejs", selection: $model.selectedInterfaceId) {
                    ForEach(interfaces, id: \.id) { interface in
                        Text(interface.name).tag(Optional(interface.id))
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                HStack {
                    Spacer()
                    Button("Importuj", action: model.confirmInterface)
                        .keyboardShortcut(.defaultAction)
                        .disabled(model.selectedInterfaceId == nil)
                }
            }
        case .done(let message):
            VStack(alignment: .leading, spacing: 8) {
                Label(message, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button("Zamknij", action: close)
                        .keyboardShortcut(.defaultAction)
                }
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
