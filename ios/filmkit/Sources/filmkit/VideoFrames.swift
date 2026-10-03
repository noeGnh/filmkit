import AVFoundation
import Flutter

enum VideoFrames {
  /// The frame closest to `positionMs`, rotation applied, as `{width, height, rgba}`. The
  /// pixels keep the decoded values: they're drawn in the image's own color space, without
  /// conversion.
  static func frame(_ url: URL, positionMs: Int64, maxDimension: Int?) async throws -> [String: Any] {
    guard FileManager.default.fileExists(atPath: url.path) else { throw FilmkitError.invalidInput("File not found: \(url.path)") }
    let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
    generator.appliesPreferredTrackTransform = true
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    if let maxDimension { generator.maximumSize = CGSize(width: maxDimension, height: maxDimension) }
    let time = CMTime(value: positionMs, timescale: 1000)

    let image: CGImage
    do {
      if #available(iOS 16.0, *) {
        image = try await generator.image(at: time).image
      } else {
        image = try generator.copyCGImage(at: time, actualTime: nil)
      }
    } catch {
      throw FilmkitError.invalidInput("No frame at \(positionMs) ms in \(url.path): \(error.localizedDescription)")
    }

    let width = image.width
    let height = image.height
    var rgba = Data(count: width * height * 4)
    let colorSpace = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
    let drawn = rgba.withUnsafeMutableBytes { buffer -> Bool in
      guard
        let context = CGContext(
          data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
          space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
      else { return false }
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }
    guard drawn else { throw FilmkitError.exportFailed("Can't draw the frame of \(url.path)") }
    return ["width": width, "height": height, "rgba": FlutterStandardTypedData(bytes: rgba)]
  }
}
