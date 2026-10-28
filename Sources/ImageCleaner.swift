import CoreImage
import ImageIO
import UniformTypeIdentifiers

enum ImageCleaner {
    /// Decode pixels, bake orientation, and encode a NEW image without source properties.
    /// A new sRGB JPEG intentionally drops HDR, depth, auxiliary images and transparency.
    static func clean(source: URL, destination: URL) throws {
        guard let input = CGImageSourceCreateWithURL(source as CFURL, nil),
              CGImageSourceGetCount(input) > 0 else { throw CleaningError.unreadableImage }
        // HEIF/RAW may contain auxiliary frames; only GIF/PNG animations are rejected.
        let type = CGImageSourceGetType(input) as String?
        if CGImageSourceGetCount(input) > 1,
           type == UTType.gif.identifier || type == UTType.png.identifier {
            throw CleaningError.animatedImage
        }
        let primaryIndex = CGImageSourceGetPrimaryImageIndex(input)
        guard let decoded = CGImageSourceCreateImageAtIndex(input, primaryIndex, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary) else { throw CleaningError.unreadableImage }
        let properties = CGImageSourceCopyPropertiesAtIndex(input, primaryIndex, nil) as? [String: Any]
        let orientation = (properties?[kCGImagePropertyOrientation as String] as? NSNumber)?.int32Value ?? 1
        let pixels = CIImage(cgImage: decoded).oriented(forExifOrientation: orientation)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CIContext(options: [.cacheIntermediates: false])
        guard let rendered = context.createCGImage(pixels, from: pixels.extent,
                                                   format: .RGBA8, colorSpace: colorSpace),
              let canvas = CGContext(data: nil, width: rendered.width, height: rendered.height,
                                     bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                     bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { throw CleaningError.cannotEncode }
        let bounds = CGRect(x: 0, y: 0, width: CGFloat(rendered.width), height: CGFloat(rendered.height))
        canvas.setFillColor(CGColor(gray: 1, alpha: 1))
        canvas.fill(bounds)
        canvas.draw(rendered, in: bounds)
        guard let opaque = canvas.makeImage(),
              let output = CGImageDestinationCreateWithURL(destination as CFURL,
                                                           UTType.jpeg.identifier as CFString, 1, nil)
        else { throw CleaningError.cannotEncode }
        CGImageDestinationAddImage(output, opaque, [
            kCGImageDestinationLossyCompressionQuality: 0.95,
            kCGImagePropertyOrientation: 1
        ] as CFDictionary)
        guard CGImageDestinationFinalize(output) else { throw CleaningError.cannotEncode }
        try verify(destination)
    }

    /// Fail closed on descriptive dictionaries or unexpected top-level properties.
    /// JPEG/ICC structure necessary for decoding is allowed, never copied from the input.
    static func verify(_ url: URL) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetType(source) as String? == UTType.jpeg.identifier,
              CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
        else { throw CleaningError.cannotEncode }
        let technical: Set<String> = ["FileSize", "PixelWidth", "PixelHeight", "DPIWidth", "DPIHeight",
                                      "Depth", "Orientation", "ColorModel", "ProfileName", "IsFloat",
                                      "IsIndexed", "HasAlpha"]
        let dictionaries: [String: Set<String>] = [
            "{JFIF}": ["JFIFVersion", "XDensity", "YDensity", "DensityUnit", "IsProgressive"],
            "{TIFF}": ["Orientation", "XResolution", "YResolution", "ResolutionUnit"],
            "{Exif}": ["ColorSpace", "PixelXDimension", "PixelYDimension", "ExifVersion",
                       "FlashPixVersion", "ComponentsConfiguration"]
        ]
        for (key, value) in properties {
            if technical.contains(key) { continue }
            guard let allowed = dictionaries[key], let fields = value as? [String: Any],
                  Set(fields.keys).isSubset(of: allowed) else { throw CleaningError.residualMetadata }
        }
    }
}
