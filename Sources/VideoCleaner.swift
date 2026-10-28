import AVFoundation
import CoreImage
import CoreVideo

enum VideoCleaner {
    /// Only decoded primary video and (if present) primary audio enter a fresh MP4.
    /// No passthrough: metadata, subtitles, timecode, auxiliary and timed-data tracks are omitted.
    static func clean(source: URL, destination: URL, cancellation: CancellationFlag,
                      progress: @escaping @Sendable (Double) -> Void) async throws {
        let asset = AVURLAsset(url: source)
        guard try await asset.load(.isReadable), !(try await asset.load(.hasProtectedContent)) else {
            throw CleaningError.unsupportedVideo
        }
        guard let video = try await asset.loadTracks(withMediaType: .video).first else {
            throw CleaningError.missingVideo
        }
        let audio = try await asset.loadTracks(withMediaType: .audio).first
        let naturalSize = try await video.load(.naturalSize)
        let transform = try await video.load(.preferredTransform)
        let frameRate = try await video.load(.nominalFrameRate)
        let mediaDuration = try await asset.load(.duration)
        let duration = mediaDuration.seconds
        guard naturalSize.width.isFinite, naturalSize.height.isFinite,
              naturalSize.width > 0, naturalSize.height > 0,
              naturalSize.width < CGFloat(Int32.max), naturalSize.height < CGFloat(Int32.max),
              [transform.a, transform.b, transform.c, transform.d, transform.tx, transform.ty].allSatisfy({ $0.isFinite }),
              duration.isFinite, duration > 0 else { throw CleaningError.unsupportedVideo }
        // H.264 requires even dimensions. Pad at most one pixel on either axis.
        let width = max(2, (Int(abs(naturalSize.width).rounded()) + 1) / 2 * 2)
        let height = max(2, (Int(abs(naturalSize.height).rounded()) + 1) / 2 * 2)
        try cancellation.check()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue(label: "app.exifbye.export", qos: .userInitiated).async {
                var reader: AVAssetReader?
                var writer: AVAssetWriter?
                do {
                    try cancellation.check()
                    let input = try AVAssetReader(asset: asset)
                    let output = try AVAssetWriter(outputURL: destination, fileType: .mp4)
                    reader = input
                    writer = output
                    output.metadata = []
                    output.shouldOptimizeForNetworkUse = true
                    let videoRead = AVAssetReaderTrackOutput(track: video, outputSettings: [
                        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                    ])
                    videoRead.alwaysCopiesSampleData = false
                    guard input.canAdd(videoRead) else { throw CleaningError.unsupportedVideo }
                    input.add(videoRead)
                    let fps = frameRate.isFinite && frameRate > 0 ? Double(frameRate) : 30
                    let bitRate = Int(min(120_000_000, max(2_000_000, Double(width) * Double(height) * fps * 0.14)))
                    let settings: [String: Any] = [
                        AVVideoCodecKey: AVVideoCodecType.h264,
                        AVVideoWidthKey: width,
                        AVVideoHeightKey: height,
                        AVVideoColorPropertiesKey: [
                            AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                            AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                            AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
                        ],
                        AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: bitRate]
                    ]
                    guard output.canApply(outputSettings: settings, forMediaType: .video) else {
                        throw CleaningError.unsupportedVideo
                    }
                    let videoWrite = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
                    videoWrite.expectsMediaDataInRealTime = false
                    videoWrite.transform = transform
                    videoWrite.metadata = []
                    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoWrite,
                        sourcePixelBufferAttributes: [
                            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                            kCVPixelBufferWidthKey as String: width,
                            kCVPixelBufferHeightKey as String: height,
                            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
                        ])
                    guard output.canAdd(videoWrite) else { throw CleaningError.unsupportedVideo }
                    output.add(videoWrite)

                    var audioRead: AVAssetReaderTrackOutput?
                    var audioWrite: AVAssetWriterInput?
                    if let audio {
                        let decoded = AVAssetReaderTrackOutput(track: audio, outputSettings: [
                            AVFormatIDKey: kAudioFormatLinearPCM,
                            AVSampleRateKey: 44_100,
                            AVNumberOfChannelsKey: 2,
                            AVLinearPCMBitDepthKey: 16,
                            AVLinearPCMIsFloatKey: false,
                            AVLinearPCMIsBigEndianKey: false,
                            AVLinearPCMIsNonInterleaved: false
                        ])
                        let encoded = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                            AVFormatIDKey: kAudioFormatMPEG4AAC,
                            AVSampleRateKey: 44_100,
                            AVNumberOfChannelsKey: 2,
                            AVEncoderBitRateKey: 192_000
                        ])
                        encoded.expectsMediaDataInRealTime = false
                        encoded.metadata = []
                        guard input.canAdd(decoded), output.canAdd(encoded) else {
                            throw CleaningError.unsupportedVideo
                        }
                        input.add(decoded)
                        output.add(encoded)
                        audioRead = decoded
                        audioWrite = encoded
                    }
                    guard output.startWriting(), input.startReading() else {
                        throw output.error ?? input.error ?? CleaningError.cannotEncode
                    }
                    output.startSession(atSourceTime: .zero)
                    let context = CIContext(options: [.cacheIntermediates: false])
                    let colorSpace = CGColorSpace(name: CGColorSpace.itur_709)!
                    var videoDone = false
                    var audioDone = audioRead == nil
                    var frames = 0
                    var lastUpdate = Date.distantPast
                    var lastAdvance = Date()
                    // Interleave tracks to avoid starving the writer. Work is off the UI thread;
                    // only one decoded video frame and one fresh output frame are held at a time.
                    while !videoDone || !audioDone {
                        try cancellation.check()
                        if input.status == .failed || output.status == .failed {
                            throw input.error ?? output.error ?? CleaningError.cannotEncode
                        }
                        var advanced = false
                        if !videoDone, videoWrite.isReadyForMoreMediaData {
                            try autoreleasepool {
                                if let sample = videoRead.copyNextSampleBuffer() {
                                    guard let original = CMSampleBufferGetImageBuffer(sample),
                                          let pool = adaptor.pixelBufferPool else {
                                        throw CleaningError.cannotEncode
                                    }
                                    var fresh: CVPixelBuffer?
                                    guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &fresh) == kCVReturnSuccess,
                                          let fresh else { throw CleaningError.cannotEncode }
                                    // Render into a NEW buffer: source attachments cannot propagate.
                                    let image = CIImage(cvPixelBuffer: original)
                                    let bounds = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
                                    let background = CIImage(color: .black).cropped(to: bounds)
                                    context.render(image.composited(over: background), to: fresh,
                                                   bounds: bounds, colorSpace: colorSpace)
                                    let time = CMSampleBufferGetPresentationTimeStamp(sample)
                                    guard adaptor.append(fresh, withPresentationTime: time) else {
                                        throw output.error ?? CleaningError.cannotEncode
                                    }
                                    frames += 1
                                    if Date().timeIntervalSince(lastUpdate) >= 0.15 {
                                        let fraction = duration.isFinite && duration > 0 ? time.seconds / duration : 0
                                        progress(min(0.99, max(0, fraction)))
                                        lastUpdate = Date()
                                    }
                                } else {
                                    videoDone = true
                                    videoWrite.markAsFinished()
                                }
                            }
                            advanced = true
                        }
                        if !audioDone, let audioRead, let audioWrite, audioWrite.isReadyForMoreMediaData {
                            try autoreleasepool {
                                if let sample = audioRead.copyNextSampleBuffer() {
                                    // PCM samples have no compressed source packets or metadata tracks.
                                    CMRemoveAllAttachments(sample)
                                    guard audioWrite.append(sample) else {
                                        throw output.error ?? CleaningError.cannotEncode
                                    }
                                } else {
                                    audioDone = true
                                    audioWrite.markAsFinished()
                                }
                            }
                            advanced = true
                        }
                        if advanced {
                            lastAdvance = Date()
                        } else {
                            // Diagnose an encoder that stopped consuming data instead of hanging forever.
                            if Date().timeIntervalSince(lastAdvance) > 60 { throw CleaningError.cannotEncode }
                            Thread.sleep(forTimeInterval: 0.002)
                        }
                    }
                    guard frames > 0, input.status == .completed else {
                        throw input.error ?? CleaningError.cannotEncode
                    }
                    try cancellation.check()
                    if duration.isFinite, duration > 0 { output.endSession(atSourceTime: mediaDuration) }
                    output.finishWriting {
                        do {
                            try cancellation.check()
                            guard output.status == .completed else {
                                throw output.error ?? CleaningError.cannotEncode
                            }
                            progress(1)
                            continuation.resume()
                        } catch { continuation.resume(throwing: error) }
                    }
                } catch {
                    reader?.cancelReading()
                    writer?.cancelWriting()
                    continuation.resume(throwing: error)
                }
            }
        }
        try cancellation.check()
        try await verify(destination)
    }

    static func verify(_ url: URL) async throws {
        let asset = AVURLAsset(url: url)
        guard try await asset.load(.metadata).isEmpty else { throw CleaningError.residualMetadata }
        let tracks = try await asset.load(.tracks)
        var videoCount = 0
        var audioCount = 0
        for track in tracks {
            if track.mediaType == .video { videoCount += 1 }
            else if track.mediaType == .audio { audioCount += 1 }
            else { throw CleaningError.residualMetadata }
            guard try await track.load(.metadata).isEmpty else { throw CleaningError.residualMetadata }
        }
        guard videoCount == 1, audioCount <= 1 else { throw CleaningError.residualMetadata }
    }
}
