import AVFoundation
import Flutter
import UIKit

/// `filmkit` method channel: `exportVideo` ({id, input, output, edit, lut}), `cancelExport`
/// ({id}), `getVideoInfo` ({path}), `getVideoFrame` ({path, positionMs, maxDimension}),
/// `exportImage` ({input, output, edit, lut, quality, keepLocation}).
/// Progress goes back to Dart as `onProgress` ({id, progress}).
public class FilmkitPlugin: NSObject, FlutterPlugin {
  private let channel: FlutterMethodChannel
  /// Running exports by id. Main thread only.
  private var jobs: [String: VideoExportJob] = [:]

  init(channel: FlutterMethodChannel) {
    self.channel = channel
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "filmkit", binaryMessenger: registrar.messenger())
    let instance = FilmkitPlugin(channel: channel)
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    jobs.values.forEach { $0.cancel() }
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "exportVideo":
      exportVideo(args, result: result)
    case "cancelExport":
      if let id = args["id"] as? String { jobs[id]?.cancel() }
      result(nil)
    case "getVideoInfo":
      let asset = AVURLAsset(url: URL(fileURLWithPath: args["path"] as! String))
      Task { @MainActor in
        do {
          result(try await VideoProbe.probe(asset).map)
        } catch {
          result(Self.flutterError(error))
        }
      }
    case "exportImage":
      let input = URL(fileURLWithPath: args["input"] as! String)
      let output = URL(fileURLWithPath: args["output"] as! String)
      let spec = EditSpec(map: args["edit"] as! [String: Any])
      let lut = Lut(map: args["lut"] as? [String: Any])
      let quality = (args["quality"] as! NSNumber).intValue
      let keepLocation = (args["keepLocation"] as! NSNumber).boolValue
      DispatchQueue.global(qos: .userInitiated).async {
        let outcome = Result {
          try ImageExporter.export(input: input, output: output, spec: spec, lut: lut, quality: quality, keepLocation: keepLocation)
        }
        DispatchQueue.main.async {
          switch outcome {
          case .success(let map): result(map)
          case .failure(let error): result(Self.flutterError(error))
          }
        }
      }
    case "getVideoFrame":
      let url = URL(fileURLWithPath: args["path"] as! String)
      let positionMs = (args["positionMs"] as! NSNumber).int64Value
      let maxDimension = (args["maxDimension"] as? NSNumber)?.intValue
      Task { @MainActor in
        do {
          result(try await VideoFrames.frame(url, positionMs: positionMs, maxDimension: maxDimension))
        } catch {
          result(Self.flutterError(error))
        }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func exportVideo(_ args: [String: Any], result: @escaping FlutterResult) {
    let id = args["id"] as! String
    let job = VideoExportJob(
      input: URL(fileURLWithPath: args["input"] as! String),
      output: URL(fileURLWithPath: args["output"] as! String),
      spec: EditSpec(map: args["edit"] as! [String: Any]),
      lut: Lut(map: args["lut"] as? [String: Any]),
      onProgress: { [channel] progress in channel.invokeMethod("onProgress", arguments: ["id": id, "progress": progress]) })
    jobs[id] = job
    job.start { [weak self] outcome in
      self?.jobs[id] = nil
      switch outcome {
      case .success(let map): result(map)
      case .failure(let error): result(Self.flutterError(error))
      }
    }
  }

  private static func flutterError(_ error: Error) -> FlutterError {
    if let error = error as? FilmkitError {
      return FlutterError(code: error.code, message: error.message, details: nil)
    }
    return FlutterError(code: "exportFailed", message: "\(error)", details: nil)
  }
}
