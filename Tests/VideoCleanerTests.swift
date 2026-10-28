import XCTest
import AVFoundation
@testable import ExifBye

final class VideoCleanerTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    func testReencodesRotatedVideoWithAudioAndRemovesLocationAndTitle() async throws {
        let source = directory.appendingPathComponent("private.mov")
        let destination = directory.appendingPathComponent("clean.mp4")
        try await fixture(at: source, audio: true)
        let original = AVURLAsset(url: source)
        let sourceMetadata = try await original.load(.metadata)
        XCTAssertFalse(sourceMetadata.isEmpty, "Fixture must actually contain metadata")
        try await VideoCleaner.clean(source: source, destination: destination,
                                     cancellation: CancellationFlag(), progress: { _ in })
        try await VideoCleaner.verify(destination)
        let clean = AVURLAsset(url: destination)
        let metadata = try await clean.load(.metadata)
        XCTAssertTrue(metadata.isEmpty)
        let videos = try await clean.loadTracks(withMediaType: .video)
        let audios = try await clean.loadTracks(withMediaType: .audio)
        XCTAssertEqual(videos.count, 1)
        XCTAssertEqual(audios.count, 1)
        let originalVideos = try await original.loadTracks(withMediaType: .video)
        let beforeTransform = try await XCTUnwrap(originalVideos.first).load(.preferredTransform)
        let afterTransform = try await XCTUnwrap(videos.first).load(.preferredTransform)
        XCTAssertEqual(afterTransform, beforeTransform)
        let duration = try await clean.load(.duration)
        XCTAssertEqual(duration.seconds, 1, accuracy: 0.15)
        // Decode a frame and PCM audio: a valid container alone is insufficient.
        let generator = AVAssetImageGenerator(asset: clean)
        generator.appliesPreferredTrackTransform = true
        let image = try generator.copyCGImage(at: CMTime(value: 1, timescale: 2), actualTime: nil)
        XCTAssertEqual(image.width, 120)
        XCTAssertEqual(image.height, 160)
        let reader = try AVAssetReader(asset: clean)
        let audio = AVAssetReaderTrackOutput(track: try XCTUnwrap(audios.first),
                                             outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM])
        reader.add(audio)
        XCTAssertTrue(reader.startReading())
        XCTAssertNotNil(audio.copyNextSampleBuffer())
        reader.cancelReading()
    }

    func testSilentVideoAndCancellation() async throws {
        let source = directory.appendingPathComponent("silent.mov")
        try await fixture(at: source, audio: false)
        let destination = directory.appendingPathComponent("clean.mp4")
        try await VideoCleaner.clean(source: source, destination: destination,
                                     cancellation: CancellationFlag(), progress: { _ in })
        let audios = try await AVURLAsset(url: destination).loadTracks(withMediaType: .audio)
        XCTAssertTrue(audios.isEmpty)
        let flag = CancellationFlag()
        flag.cancel()
        do {
            try await VideoCleaner.clean(source: source,
                destination: directory.appendingPathComponent("cancelled.mp4"), cancellation: flag,
                progress: { _ in })
            XCTFail("Export must respect cancellation")
        } catch is CancellationError { /* expected */ }
    }

    func testVerifierRejectsSourceMetadata() async throws {
        let source = directory.appendingPathComponent("private.mov")
        try await fixture(at: source, audio: false)
        do {
            try await VideoCleaner.verify(source)
            XCTFail("Unclean source must be rejected")
        } catch CleaningError.residualMetadata { /* expected */ }
    }

    private func fixture(at url: URL, audio: Bool) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let location = AVMutableMetadataItem()
        location.identifier = .quickTimeMetadataLocationISO6709
        location.value = "+41.8902+012.4922/" as NSString
        let title = AVMutableMetadataItem()
        title.identifier = .commonIdentifierTitle
        title.value = "Private owner and title" as NSString
        writer.metadata = [location, title]
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 160, AVVideoHeightKey: 120
        ])
        video.transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 120, ty: 0)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 160, kCVPixelBufferHeightKey as String: 120
            ])
        writer.add(video)
        let sound = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 128_000
        ])
        if audio { writer.add(sound) }
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        if audio {
            try await waitUntilReady(sound)
            XCTAssertTrue(sound.append(try silentPCM()))
            sound.markAsFinished()
        }
        for index in 0..<12 {
            try await waitUntilReady(video)
            var buffer: CVPixelBuffer?
            let pool = try XCTUnwrap(adaptor.pixelBufferPool)
            XCTAssertEqual(CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer), kCVReturnSuccess)
            let pixels = try XCTUnwrap(buffer)
            CVPixelBufferLockBaseAddress(pixels, [])
            if let address = CVPixelBufferGetBaseAddress(pixels) {
                memset(address, 128, CVPixelBufferGetBytesPerRow(pixels) * CVPixelBufferGetHeight(pixels))
            }
            CVPixelBufferUnlockBaseAddress(pixels, [])
            XCTAssertTrue(adaptor.append(pixels, withPresentationTime: CMTime(value: Int64(index), timescale: 12)))
        }
        video.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed, writer.error?.localizedDescription ?? "")
    }

    private func waitUntilReady(_ input: AVAssetWriterInput) async throws {
        let deadline = Date().addingTimeInterval(10)
        while !input.isReadyForMoreMediaData {
            if Date() > deadline { throw CleaningError.cannotEncode }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    private func silentPCM() throws -> CMSampleBuffer {
        let count = 44_100
        var description = AudioStreamBasicDescription(mSampleRate: 44_100,
            mFormatID: kAudioFormatLinearPCM, mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4, mChannelsPerFrame: 2,
            mBitsPerChannel: 16, mReserved: 0)
        var format: CMAudioFormatDescription?
        XCTAssertEqual(CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &description,
            layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil,
            formatDescriptionOut: &format), noErr)
        var block: CMBlockBuffer?
        XCTAssertEqual(CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault,
            memoryBlock: nil, blockLength: count * 4, blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil, offsetToData: 0, dataLength: count * 4, flags: 0,
            blockBufferOut: &block), kCMBlockBufferNoErr)
        let data = try XCTUnwrap(block)
        XCTAssertEqual(CMBlockBufferFillDataBytes(with: 0, blockBuffer: data,
            offsetIntoDestination: 0, dataLength: count * 4), kCMBlockBufferNoErr)
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 44_100),
                                        presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
        var sampleSize = 4
        var sample: CMSampleBuffer?
        XCTAssertEqual(CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: data,
            formatDescription: try XCTUnwrap(format), sampleCount: count, sampleTimingEntryCount: 1,
            sampleTimingArray: &timing, sampleSizeEntryCount: 1, sampleSizeArray: &sampleSize,
            sampleBufferOut: &sample), noErr)
        return try XCTUnwrap(sample)
    }
}
