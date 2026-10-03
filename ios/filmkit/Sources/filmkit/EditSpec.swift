import CoreGraphics
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

  private static func even(_ value: CGFloat) -> Int { max(2, Int((value / 2).rounded()) * 2) }
}
