import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct MediaPicker: UIViewControllerRepresentable {
    let onSelection: ([PHPickerResult]) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        // The system picker gives access only to selected items; no full-library permission.
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .any(of: [.images, .videos])
        config.selectionLimit = 0
        config.selection = .ordered
        config.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onSelection) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onSelection: ([PHPickerResult]) -> Void
        init(_ onSelection: @escaping ([PHPickerResult]) -> Void) { self.onSelection = onSelection }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            onSelection(results)
        }
    }
}

enum MediaImporter {
    enum Kind { case photo, video }

    private final class Transfer: @unchecked Sendable {
        private let lock = NSLock()
        private var progress: Progress?
        private var cancelled = false
        func install(_ value: Progress) {
            lock.lock()
            progress = value
            let shouldCancel = cancelled
            lock.unlock()
            if shouldCancel { value.cancel() }
        }
        func cancel() {
            lock.lock()
            cancelled = true
            let value = progress
            lock.unlock()
            value?.cancel()
        }
    }

    static func load(_ result: PHPickerResult, into directory: URL) async throws -> (URL, Kind) {
        let provider = result.itemProvider
        let kind: Kind = provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) ? .video : .photo
        let type = kind == .video ? UTType.movie.identifier : UTType.image.identifier
        guard provider.hasItemConformingToTypeIdentifier(type) else { throw CleaningError.importFailed }
        let transfer = Transfer()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let progress = provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
                    do {
                        guard let url else { throw error ?? CleaningError.importFailed }
                        let destination = directory.appendingPathComponent("input")
                            .appendingPathExtension(url.pathExtension)
                        // Provider URLs expire on returning from this callback. Copy here, before resuming.
                        try FileManager.default.copyItem(at: url, to: destination)
                        continuation.resume(returning: (destination, kind))
                    } catch { continuation.resume(throwing: error) }
                }
                transfer.install(progress)
            }
        } onCancel: { transfer.cancel() }
    }
}
