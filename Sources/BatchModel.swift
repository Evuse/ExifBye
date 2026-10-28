import PhotosUI
import SwiftUI
import UIKit

struct BatchItem: Identifiable {
    enum State {
        case pending, working, saved, failed(String)
    }
    let id = UUID()
    let selection: PHPickerResult
    var state: State = .pending
}

@MainActor
final class BatchModel: ObservableObject {
    @Published private(set) var items: [BatchItem] = []
    @Published private(set) var isBusy = false
    @Published private(set) var isStopping = false
    @Published private(set) var fraction = 0.0
    @Published private(set) var stage = ""
    @Published private(set) var activeIndex: Int?
    @Published var message: String?
    private var task: Task<Void, Never>?
    private var cancellation = CancellationFlag()

    init() {
        // Remove only this app's own abandoned staging directories after a crash/force quit.
        let temporary = FileManager.default.temporaryDirectory
        if let urls = try? FileManager.default.contentsOfDirectory(at: temporary,
                                                                  includingPropertiesForKeys: nil) {
            for url in urls where url.lastPathComponent.hasPrefix("ExifBye-") {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    var savedCount: Int { items.filter { if case .saved = $0.state { return true }; return false }.count }
    var failedCount: Int { items.filter { if case .failed = $0.state { return true }; return false }.count }
    var remainingCount: Int { items.count - savedCount }

    func select(_ results: [PHPickerResult]) {
        guard !isBusy, !results.isEmpty else { return }
        items = results.map { BatchItem(selection: $0) }
        stage = ""
        fraction = 0
        message = nil
    }

    func start() {
        guard !isBusy, remainingCount > 0 else { return }
        isBusy = true
        isStopping = false
        message = nil
        cancellation = CancellationFlag()
        let flag = cancellation
        task = Task {
            let previousIdleSetting = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = true
            defer {
                UIApplication.shared.isIdleTimerDisabled = previousIdleSetting
                isBusy = false
                isStopping = false
                activeIndex = nil
                task = nil
            }
            do {
                stage = "Autorizzazione al salvataggio…"
                try await PhotoLibrary.requestAddAccess()
                try Task.checkCancellation()
                for index in items.indices {
                    if case .saved = items[index].state { continue }
                    try Task.checkCancellation()
                    activeIndex = index
                    fraction = 0
                    items[index].state = .working
                    do {
                        try await process(items[index].selection, flag: flag)
                        // A save already committed by Photos remains a success even if Stop was tapped.
                        items[index].state = .saved
                        fraction = 1
                    } catch {
                        if Task.isCancelled || error is CancellationError {
                            items[index].state = .pending
                            throw CancellationError()
                        }
                        items[index].state = .failed(error.localizedDescription)
                    }
                }
                stage = failedCount == 0 ? "Pulizia completata" : "Completato con \(failedCount) errori"
            } catch is CancellationError {
                stage = "Interrotto: puoi riprendere gli elementi rimasti"
            } catch {
                stage = "Salvataggio non disponibile"
                message = error.localizedDescription
            }
        }
    }

    func stop() {
        guard isBusy else { return }
        isStopping = true
        cancellation.cancel()
        task?.cancel()
    }

    private func process(_ result: PHPickerResult, flag: CancellationFlag) async throws {
        // One directory per item; never stage an entire large batch on disk.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExifBye-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete])
        defer { try? FileManager.default.removeItem(at: directory) }
        stage = "Importazione (download se su iCloud)…"
        let (source, kind) = try await MediaImporter.load(result, into: directory)
        try Task.checkCancellation()
        let output = directory.appendingPathComponent(kind == .photo ? "clean.jpg" : "clean.mp4")
        stage = "Ricodifica e rimozione metadati…"
        if kind == .photo {
            // ImageIO and Core Image work must not block the main actor.
            try await Task.detached(priority: .userInitiated) {
                try flag.check()
                try autoreleasepool { try ImageCleaner.clean(source: source, destination: output) }
                try flag.check()
            }.value
        } else {
            try await VideoCleaner.clean(source: source, destination: output, cancellation: flag) { [weak self] value in
                Task { @MainActor [weak self] in self?.fraction = value }
            }
        }
        try Task.checkCancellation()
        stage = "Salvataggio della copia clean…"
        try await PhotoLibrary.save(output, kind: kind)
    }
}
