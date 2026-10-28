import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import ExifBye

final class ImageCleanerTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    func testRemovesGPSCameraDateIPTCAndBakesOrientation() throws {
        let source = directory.appendingPathComponent("private.jpg")
        let output = directory.appendingPathComponent("clean.jpg")
        try fixture(at: source, orientation: 6)
        let before = try properties(source)
        XCTAssertNotNil(before[kCGImagePropertyGPSDictionary as String])
        XCTAssertNotNil(before[kCGImagePropertyExifDictionary as String])

        try ImageCleaner.clean(source: source, destination: output)
        let after = try properties(output)
        XCTAssertNil(after[kCGImagePropertyGPSDictionary as String])
        XCTAssertNil(after[kCGImagePropertyIPTCDictionary as String])
        let tiff = after[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
        XCTAssertNil(tiff?[kCGImagePropertyTIFFMake as String])
        XCTAssertNil(tiff?[kCGImagePropertyTIFFModel as String])
        let exif = after[kCGImagePropertyExifDictionary as String] as? [String: Any]
        XCTAssertNil(exif?[kCGImagePropertyExifDateTimeOriginal as String])
        XCTAssertNil(exif?[kCGImagePropertyExifUserComment as String])
        XCTAssertEqual((after[kCGImagePropertyPixelWidth as String] as? NSNumber)?.intValue, 20)
        XCTAssertEqual((after[kCGImagePropertyPixelHeight as String] as? NSNumber)?.intValue, 40)
        let decoded = try XCTUnwrap(CGImageSourceCreateWithURL(output as CFURL, nil))
        XCTAssertNotNil(CGImageSourceCreateImageAtIndex(decoded, 0, nil))
        // The original remains untouched.
        XCTAssertNotNil(try properties(source)[kCGImagePropertyGPSDictionary as String])
        try ImageCleaner.verify(output)
    }

    func testRejectsUncleanImageInsteadOfSavingIt() throws {
        let source = directory.appendingPathComponent("private.jpg")
        try fixture(at: source)
        XCTAssertThrowsError(try ImageCleaner.verify(source)) { error in
            guard case CleaningError.residualMetadata = error else {
                return XCTFail("Expected residual metadata, got \(error)")
            }
        }
    }

    func testRejectsCorruptInput() throws {
        let source = directory.appendingPathComponent("broken.jpg")
        try Data("not an image".utf8).write(to: source)
        XCTAssertThrowsError(try ImageCleaner.clean(source: source,
            destination: directory.appendingPathComponent("clean.jpg")))
    }

    func testDoesNotSilentlyFlattenAnimatedGIF() throws {
        let source = directory.appendingPathComponent("animated.gif")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(source as CFURL,
                                                                       UTType.gif.identifier as CFString, 2, nil))
        let image = try pixels()
        for _ in 0..<2 {
            CGImageDestinationAddImage(destination, image, [
                kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]
            ] as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        XCTAssertThrowsError(try ImageCleaner.clean(source: source,
            destination: directory.appendingPathComponent("clean.jpg"))) { error in
            guard case CleaningError.animatedImage = error else { return XCTFail("\(error)") }
        }
    }

    private func fixture(at url: URL, orientation: Int = 1) throws {
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL,
            UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try pixels(), [
            kCGImagePropertyOrientation: orientation,
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 41.8902,
                kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 12.4922,
                kCGImagePropertyGPSLongitudeRef: "E"
            ],
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFMake: "Private camera maker",
                kCGImagePropertyTIFFModel: "Personal device",
                kCGImagePropertyTIFFArtist: "Private owner"
            ],
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: "2020:01:02 03:04:05",
                kCGImagePropertyExifUserComment: "Private comment"
            ],
            kCGImagePropertyIPTCDictionary: [kCGImagePropertyIPTCKeywords: ["private keyword"]]
        ] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    private func pixels() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: 40, height: 20,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 0.1, green: 0.6, blue: 0.4, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
        return try XCTUnwrap(context.makeImage())
    }

    private func properties(_ url: URL) throws -> [String: Any] {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
    }
}
