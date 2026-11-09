import AppKit
import Foundation
import GrentonKit
import UniformTypeIdentifiers

/// The import window's state: pick a file (.zip archive or .omp project) or download from Object Manager.
@Observable
@MainActor
final class ImportModel {
    enum Source: Hashable {
        case file
        case objectManager
    }

    enum Step {
        case idle
        case working(String)
        /// A project with several interfaces: the user picks one. Holds the file's bytes for `InterfaceStore`.
        case choosingInterface(Data, [ProjectInterface])
        case done(String)
        case failed(String)
    }

    var source: Source = .file
    var host = ""
    var pin = ""
    var selectedInterfaceId: String?
    private(set) var step: Step = .idle

    private let app: AppModel

    init(app: AppModel) {
        self.app = app
    }

    var isWorking: Bool {
        if case .working = step { true } else { false }
    }

    var canDownload: Bool {
        !host.trimmingCharacters(in: .whitespaces).isEmpty && !pin.trimmingCharacters(in: .whitespaces).isEmpty && !isWorking
    }

    func reset() {
        step = .idle
    }

    // MARK: - File

    func pickFile() {
        let panel = NSOpenPanel()
        panel.title = "Wybierz interfejs Grenton"
        panel.message = "Archiwum interfejsu z Object Managera (.zip) albo plik projektu (.omp)"
        panel.allowedContentTypes = [.zip] + [UTType(filenameExtension: "omp")].compactMap { $0 }
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importFile(at: url)
    }

    func importFile(at url: URL) {
        let isProject = url.pathExtension.lowercased() == "omp"
        // The library rejects larger files only after they are read; check before reading a file picked by mistake.
        let limit = isProject ? ProjectFile.maxBytes : ProvisioningClient.maxPayloadBytes
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > limit {
            step = .failed("Plik jest za duży na interfejs Grenton (ponad \(limit / 1024 / 1024) MB).")
            return
        }
        step = .working("Wczytywanie \(url.lastPathComponent)…")
        Task {
            do {
                let data = try Data(contentsOf: url)
                if isProject {
                    try await importProject(data)
                } else {
                    try await app.useArchive(data)
                    step = .done("Zapisano interfejs z archiwum.")
                }
            } catch {
                step = .failed(Self.describe(error))
            }
        }
    }

    private func importProject(_ data: Data) async throws {
        let interfaces = try ProjectFile(data: data).interfaces
        switch interfaces.count {
        case 0:
            throw ProvisioningError.interfaceNotFound
        case 1:
            try await useProject(data, id: nil)
        default:
            selectedInterfaceId = interfaces.first?.id
            step = .choosingInterface(data, interfaces)
        }
    }

    func confirmInterface() {
        guard case .choosingInterface(let data, _) = step, let id = selectedInterfaceId else { return }
        step = .working("Importowanie interfejsu…")
        Task {
            do {
                try await useProject(data, id: id)
            } catch {
                step = .failed(Self.describe(error))
            }
        }
    }

    private func useProject(_ data: Data, id: String?) async throws {
        try await app.useProject(data, interfaceId: id)
        step = .done("Zapisano interfejs z pliku projektu.")
    }

    // MARK: - Object Manager

    func download() {
        let host = host.trimmingCharacters(in: .whitespaces)
        let pin = pin
        step = .working("Pobieranie z Object Managera…")
        Task {
            do {
                let archive = try await ProvisioningClient(host: host).fetchInterfaceArchive(pin: pin)
                try await app.useArchive(archive)
                self.pin = ""
                step = .done("Pobrano i zapisano interfejs.")
            } catch {
                step = .failed(Self.describe(error))
            }
        }
    }

    private static func describe(_ error: any Error) -> String {
        switch error as? ProvisioningError {
        case .authenticationFailed?: return "Object Manager odrzucił PIN albo okno „Wyślij do urządzeń mobilnych” jest zamknięte."
        case .connection?: return "Nie można połączyć się z Object Managerem. Sprawdź adres i czy okno wysyłania jest otwarte."
        case .interfaceNotFound?: return "Plik nie zawiera interfejsu mobilnego."
        case .interfaceAmbiguous?: return "Plik zawiera kilka interfejsów — wybierz jeden."
        case .invalidData?: return "To nie jest interfejs Grenton (archiwum .zip z Object Managera albo projekt .omp)."
        default: return error.localizedDescription
        }
    }
}
