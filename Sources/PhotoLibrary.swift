import Photos

enum PhotoLibrary {
    static func requestAddAccess() async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw CleaningError.photoPermission }
    }

    static func save(_ url: URL, kind: MediaImporter.Kind) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            let options = PHAssetResourceCreationOptions()
            options.originalFilename = "Clean-\(UUID().uuidString).\(kind == .photo ? "jpg" : "mp4")"
            request.addResource(with: kind == .photo ? .photo : .video, fileURL: url, options: options)
            // Photos will create a new library record. Never copy location or date from the source.
            request.location = nil
            request.creationDate = Date()
        }
    }
}
