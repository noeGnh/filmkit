import CoreGraphics
import CoreImage
import Flutter
import Foundation

/// Error reported to Dart as a `FilmkitException` with this `code` (a `FilmkitErrorCode` name).
struct FilmkitError: Error {
  let code: String
  let message: String

  static func invalidInput(_ message: String) -> FilmkitError { FilmkitError(code: "invalidInput", message: message) }
  static let cancelled = FilmkitError(code: "cancelled", message: "Export cancelled")
  static func exportFailed(_ message: String) -> FilmkitError { FilmkitError(code: "exportFailed", message: message) }
}

/// Normalized rect in displayed coordinates, origin top left.
struct CropRect: Equatable {
  let left: CGFloat
  let top: CGFloat
  let right: CGFloat
  let bottom: CGFloat

  static let full = CropRect(left: 0, top: 0, right: 1, bottom: 1)
}

/// The Dart `EditSpec`, as sent by `EditSpec.toJson` (already validated on the Dart side).
struct EditSpec: Equatable {
  let trimStartMs: Int64
  let trimEndMs: Int64?
  let crop: CropRect
  let maxDimension: Int?

  init(trimStartMs: Int64, trimEndMs: Int64?, crop: CropRect, maxDimension: Int?) {
    self.trimStartMs = trimStartMs
    self.trimEndMs = trimEndMs
    self.crop = crop
    self.maxDimension = maxDimension
  }

  /// Flutter sends `null` as `NSNull`, which the `as?` casts turn into `nil`.
  init(map: [String: Any]) {
    let crop = (map["crop"] as? [NSNumber])?.map { CGFloat($0.doubleValue) }
    self.init(
      trimStartMs: (map["trimStartMs"] as? NSNumber)?.int64Value ?? 0,
      trimEndMs: (map["trimEndMs"] as? NSNumber)?.int64Value,
      crop: crop.map { CropRect(left: $0[0], top: $0[1], right: $0[2], bottom: $0[3]) } ?? .full,
      maxDimension: (map["maxDimension"] as? NSNumber)?.intValue)
  }
}

enum ExportGeometry {
  /// Output size: the crop of the displayed frame, scaled down so that its longest side fits
  /// `maxDimension`, rounded to even values (required by most encoders).
  static func outputSize(displayWidth: Int, displayHeight: Int, crop: CropRect, maxDimension: Int?) -> (width: Int, height: Int) {
    let width = (crop.right - crop.left) * CGFloat(displayWidth)
    let height = (crop.bottom - crop.top) * CGFloat(displayHeight)
    let scale = maxDimension.map { min(1, CGFloat($0) / max(width, height)) } ?? 1
    return (even(width * scale), even(height * scale))
  }

  /// The crop in Core Image coordinates (pixels, origin bottom left) of the displayed frame.
  static func coreImageRect(displayWidth: Int, displayHeight: Int, crop: CropRect) -> CGRect {
    let width = CGFloat(displayWidth)
    let height = CGFloat(displayHeight)
    return CGRect(
      x: crop.left * width, y: (1 - crop.bottom) * height,
      width: (crop.right - crop.left) * width, height: (crop.bottom - crop.top) * height)
  }

  /// Photo output size: as `outputSize`, rounded to the nearest pixel (no even constraint).
  static func imageOutputSize(displayWidth: Int, displayHeight: Int, crop: CropRect, maxDimension: Int?) -> (width: Int, height: Int) {
    let width = (crop.right - crop.left) * CGFloat(displayWidth)
    let height = (crop.bottom - crop.top) * CGFloat(displayHeight)
    let scale = maxDimension.map { min(1, CGFloat($0) / max(width, height)) } ?? 1
    return (max(1, Int((width * scale).rounded())), max(1, Int((height * scale).rounded())))
  }

  private static func even(_ value: CGFloat) -> Int { max(2, Int((value / 2).rounded()) * 2) }
}

/// A 3D LUT as sent by Dart: `size`³ RGB triplets in 0..1, red varying fastest.
struct Lut {
  let size: Int
  let data: [Float]
  /// `inputCubeData` of the Core Image color cube filters.
  let cubeData: Data

  /// Applies the table to `image` with Core Image, in `colorSpace`: the encoding of the values
  /// the preview grades (`videoColorSpace` for video frames, sRGB for photos).
  func apply(to image: CIImage, colorSpace: CGColorSpace) -> CIImage {
    // CIFilter isn't thread-safe: one per call.
    let filter = CIFilter(name: "CIColorCubeWithColorSpace")!
    filter.setValue(size, forKey: "inputCubeDimension")
    filter.setValue(cubeData, forKey: "inputCubeData")
    filter.setValue(colorSpace, forKey: "inputColorSpace")
    filter.setValue(image, forKey: kCIInputImageKey)
    return filter.outputImage!
  }

  /// The color space in which the table applies to video: CoreMedia's BT.709, the one of
  /// decoded SDR video frames (and of `getVideoFrame`), so that the table grades the values the
  /// preview shows. sRGB (right for still images) or ITU 709 give visibly different results.
  /// Public as `CGColorSpace.coreMedia709` since iOS 18; created by name for older versions.
  static let videoColorSpace = CGColorSpace(name: "kCGColorSpaceCoreMedia709" as CFString) ?? CGColorSpace(name: CGColorSpace.itur_709)!

  init(size: Int, data: [Float]) {
    precondition(data.count == size * size * size * 3, "LUT data must hold size³ × 3 values")
    self.size = size
    self.data = data
    // RGBA floats, red varying fastest.
    var rgba = [Float](repeating: 1, count: size * size * size * 4)
    for i in 0..<(size * size * size) {
      rgba[i * 4] = data[i * 3]
      rgba[i * 4 + 1] = data[i * 3 + 1]
      rgba[i * 4 + 2] = data[i * 3 + 2]
    }
    cubeData = rgba.withUnsafeBufferPointer { Data(buffer: $0) }
  }

  init?(map: [String: Any]?) {
    guard let map, let size = (map["size"] as? NSNumber)?.intValue,
      let typed = map["data"] as? FlutterStandardTypedData
    else { return nil }
    let data: [Float] = typed.data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    self.init(size: size, data: data)
  }
}
