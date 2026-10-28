import Foundation

enum CleaningError: LocalizedError {
    case unreadableImage
    case animatedImage
    case cannotEncode
    case residualMetadata
    case missingVideo
    case unsupportedVideo
    case importFailed
    case photoPermission
    case interrupted

    var errorDescription: String? {
        switch self {
        case .unreadableImage: return "Immagine non leggibile o formato non supportato da iOS."
        case .animatedImage: return "Le immagini animate non sono supportate: esportale come video per conservarne l’animazione."
        case .cannotEncode: return "Impossibile ricodificare il file. Verifica formato e spazio disponibile."
        case .residualMetadata: return "La verifica ha rilevato metadati inattesi. La copia non è stata salvata."
        case .missingVideo: return "Il file non contiene una traccia video leggibile."
        case .unsupportedVideo: return "Video non supportato dal codificatore di questo dispositivo (formato, dimensioni o protezione)."
        case .importFailed: return "Impossibile importare il file. Se è su iCloud, verifica la connessione e riprova."
        case .photoPermission: return "Consenti l’aggiunta di foto in Impostazioni → ExifBye → Foto, poi riprova."
        case .interrupted: return "Operazione interrotta. Le copie già salvate restano nel rullino."
        }
    }
}

/// Shared with the export worker; cancellation never accesses UIKit off the main thread.
final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    func check() throws {
        lock.lock()
        let value = cancelled
        lock.unlock()
        if value { throw CancellationError() }
    }
}
