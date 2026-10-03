import CoreImage
import ImageIO
import UniformTypeIdentifiers

/// Photo export: orient, crop, LUT (sRGB), Lanczos scale, JPEG with the capture metadata.
enum ImageExporter {
  private static let context = CIContext()
  private static let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

  /// Blocking: call it off the main thread.
  static func export(
    input: URL, output: URL, spec: EditSpec, lut: Lut?, quality: Int, keepLocation: Bool
  ) throws -> [String: Any] {
    guard FileManager.default.fileExists(atPath: input.path) else { throw FilmkitError.invalidInput("File not found: \(input.path)") }
    guard let source = CGImageSourceCreateWithURL(input as CFURL, nil), CGImageSourceGetCount(source) > 0,
      var image = CIImage(contentsOf: input, options: [.applyOrientationProperty: true])
    else { throw FilmkitError.invalidInput("Not a supported image: \(input.path)") }

    // Displayed orientation, origin at zero.
    image = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
    let displayWidth = Int(image.extent.width.rounded())
    let displayHeight = Int(image.extent.height.rounded())
    let size = ExportGeometry.imageOutputSize(
      displayWidth: displayWidth, displayHeight: displayHeight, crop: spec.crop, maxDimension: spec.maxDimension)

    if let lut { image = lut.apply(to: image, colorSpace: srgb) }
    let cropRect = ExportGeometry.coreImageRect(displayWidth: displayWidth, displayHeight: displayHeight, crop: spec.crop)
    image = image.cropped(to: cropRect)
      .transformed(by: CGAffineTransform(translationX: -cropRect.minX, y: -cropRect.minY))
      // Lanczos samples outside the crop at the edges: repeat the edge pixels there.
      .clampedToExtent()
    let scaleY = CGFloat(size.height) / cropRect.height
    let scaleX = CGFloat(size.width) / cropRect.width
    if let lanczos = CIFilter(name: "CILanczosScaleTransform") {
      lanczos.setValue(image, forKey: kCIInputImageKey)
      lanczos.setValue(scaleY, forKey: kCIInputScaleKey)
      lanczos.setValue(scaleX / scaleY, forKey: kCIInputAspectRatioKey)
      image = lanczos.outputImage!
    }
    let outputRect = CGRect(x: 0, y: 0, width: size.width, height: size.height)
    guard let rendered = context.createCGImage(image, from: outputRect, format: .RGBA8, colorSpace: srgb) else {
      throw FilmkitError.exportFailed("Can't render \(input.path)")
    }

    try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
      throw FilmkitError.exportFailed("Can't write \(output.path)")
    }
    let sourceProperties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
    var properties = metadata(sourceProperties, keepLocation: keepLocation)
    properties[kCGImageDestinationLossyCompressionQuality] = Double(quality) / 100
    CGImageDestinationAddImage(destination, rendered, properties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { throw FilmkitError.exportFailed("Can't write \(output.path)") }
    return ["path": output.path, "width": size.width, "height": size.height]
  }

  /// The capture metadata (EXIF, TIFF, and GPS if `keepLocation`) of the source; the pixels
  /// are already oriented and resized.
  static func metadata(_ source: [CFString: Any], keepLocation: Bool) -> [CFString: Any] {
    var properties: [CFString: Any] = [kCGImagePropertyOrientation: 1]
    if var exif = source[kCGImagePropertyExifDictionary] as? [CFString: Any] {
      exif[kCGImagePropertyExifPixelXDimension] = nil
      exif[kCGImagePropertyExifPixelYDimension] = nil
      exif[kCGImagePropertyExifSubjectArea] = nil
      properties[kCGImagePropertyExifDictionary] = exif
    }
    if var tiff = source[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
      tiff[kCGImagePropertyTIFFOrientation] = 1
      properties[kCGImagePropertyTIFFDictionary] = tiff
    }
    if keepLocation, let gps = source[kCGImagePropertyGPSDictionary] {
      properties[kCGImagePropertyGPSDictionary] = gps
    }
    return properties
  }
}
