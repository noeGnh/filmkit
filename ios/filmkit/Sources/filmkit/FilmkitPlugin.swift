import AVFoundation
import CoreImage
import Flutter
import UIKit

/// Video export spike: crop + trim + resize (+ HDR to SDR) with AVFoundation.
public class FilmkitPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "filmkit", binaryMessenger: registrar.messenger())
    let instance = FilmkitPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPlatformVersion":
      result("iOS " + UIDevice.current.systemVersion)
    case "exportVideo":
      let args = call.arguments as! [String: Any]
      Task {
        do {
          let output = try await exportVideo(args)
          await MainActor.run { result(output) }
        } catch {
          await MainActor.run { result(FlutterError(code: "EXPORT_FAILED", message: "\(error)", details: nil)) }
        }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Same arguments as on Android: `input`, `output`, `startMs`, `endMs`, `crop` ([left, top,
  /// right, bottom], normalized, displayed coordinates) and `maxDimension`.
  private func exportVideo(_ args: [String: Any]) async throws -> [String: Any] {
    let input = URL(fileURLWithPath: args["input"] as! String)
    let output = URL(fileURLWithPath: args["output"] as! String)
    let startMs = (args["startMs"] as! NSNumber).int64Value
    let endMs = (args["endMs"] as! NSNumber).int64Value
    let crop = (args["crop"] as! [NSNumber]).map { CGFloat($0.doubleValue) }
    let maxDimension = CGFloat((args["maxDimension"] as! NSNumber).doubleValue)

    let asset = AVURLAsset(url: input)
    guard let track = try await asset.loadTracks(withMediaType: .video).first else {
      throw NSError(domain: "filmkit", code: 1, userInfo: [NSLocalizedDescriptionKey: "No video track"])
    }
    let (naturalSize, transform) = try await track.load(.naturalSize, .preferredTransform)
    let displayed = naturalSize.applying(transform)
    let displayWidth = abs(displayed.width)
    let displayHeight = abs(displayed.height)

    let (left, top, right, bottom) = (crop[0], crop[1], crop[2], crop[3])
    let cropWidth = (right - left) * displayWidth
    let cropHeight = (bottom - top) * displayHeight
    let scale = min(1, maxDimension / max(cropWidth, cropHeight))
    let outWidth = even(cropWidth * scale)
    let outHeight = even(cropHeight * scale)

    // Core Image coordinates have their origin at the bottom left.
    let cropRect = CGRect(
      x: left * displayWidth, y: (1 - bottom) * displayHeight, width: cropWidth, height: cropHeight)
    let sx = CGFloat(outWidth) / cropWidth
    let sy = CGFloat(outHeight) / cropHeight

    let handler: (AVAsynchronousCIImageFilteringRequest) -> Void = { request in
      let image = request.sourceImage
        .cropped(to: cropRect)
        .transformed(by: CGAffineTransform(translationX: -cropRect.minX, y: -cropRect.minY))
        .transformed(by: CGAffineTransform(scaleX: sx, y: sy))
      request.finish(with: image, context: nil)
    }
    let composition: AVMutableVideoComposition
    if #available(iOS 16.0, *) {
      composition = try await AVMutableVideoComposition.videoComposition(
        with: asset, applyingCIFiltersWithHandler: handler)
    } else {
      composition = AVMutableVideoComposition(asset: asset, applyingCIFiltersWithHandler: handler)
    }
    composition.renderSize = CGSize(width: outWidth, height: outHeight)
    // SDR output (HDR sources are tone mapped).
    composition.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
    composition.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
    composition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2

    try? FileManager.default.removeItem(at: output)
    guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality)
    else {
      throw NSError(domain: "filmkit", code: 2, userInfo: [NSLocalizedDescriptionKey: "No export session"])
    }
    session.videoComposition = composition
    session.timeRange = CMTimeRange(
      start: CMTime(value: startMs, timescale: 1000), end: CMTime(value: endMs, timescale: 1000))

    let startedAt = Date()
    if #available(iOS 18.0, *) {
      try await session.export(to: output, as: .mp4)
    } else {
      session.outputURL = output
      session.outputFileType = .mp4
      await session.export()
      if let error = session.error { throw error }
    }

    return [
      "output": output.path,
      "elapsedMs": Int(Date().timeIntervalSince(startedAt) * 1000),
      "width": outWidth,
      "height": outHeight,
      "videoEncoder": "AVAssetExportPresetHighestQuality",
    ]
  }

  private func even(_ value: CGFloat) -> Int { max(2, Int((value / 2).rounded()) * 2) }
}
