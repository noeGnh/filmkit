import CoreImage
import Flutter
import UIKit

/// LUT parity spike: applies a 3D LUT to an RGBA8 image with Core Image, in one of three modes.
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
    case "applyLutImage":
      applyLutImage(call, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Arguments: `rgba`, `width`, `height`, `lutSize`, `lut` (ARGB colors indexed by
  /// `(r * N + g) * N + b`, as on Android) and `mode`:
  /// - `linear`: CIColorCube with the default context (linear working space),
  /// - `srgbSpace`: CIColorCubeWithColorSpace in sRGB,
  /// - `noColorManagement`: CIColorCube with color management disabled.
  private func applyLutImage(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as! [String: Any]
    let rgba = (args["rgba"] as! FlutterStandardTypedData).data
    let width = args["width"] as! Int
    let height = args["height"] as! Int
    let n = args["lutSize"] as! Int
    let lutData = (args["lut"] as! FlutterStandardTypedData).data
    let mode = args["mode"] as! String

    let lut: [Int32] = lutData.withUnsafeBytes { Array($0.bindMemory(to: Int32.self)) }

    // Core Image cubes are RGBA floats with red varying fastest.
    var cube = [Float](repeating: 0, count: n * n * n * 4)
    for r in 0..<n {
      for g in 0..<n {
        for b in 0..<n {
          let c = lut[(r * n + g) * n + b]
          let i = ((b * n + g) * n + r) * 4
          cube[i] = Float((c >> 16) & 0xFF) / 255
          cube[i + 1] = Float((c >> 8) & 0xFF) / 255
          cube[i + 2] = Float(c & 0xFF) / 255
          cube[i + 3] = 1
        }
      }
    }
    let cubeData = cube.withUnsafeBufferPointer { Data(buffer: $0) }

    let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
    let noColorManagement = mode == "noColorManagement"
    let input = CIImage(
      bitmapData: rgba, bytesPerRow: width * 4, size: CGSize(width: width, height: height),
      format: .RGBA8, colorSpace: noColorManagement ? nil : srgb)

    let filter: CIFilter
    if mode == "srgbSpace" {
      filter = CIFilter(name: "CIColorCubeWithColorSpace")!
      filter.setValue(srgb, forKey: "inputColorSpace")
    } else {
      filter = CIFilter(name: "CIColorCube")!
    }
    filter.setValue(n, forKey: "inputCubeDimension")
    filter.setValue(cubeData, forKey: "inputCubeData")
    filter.setValue(input, forKey: kCIInputImageKey)

    let context =
      noColorManagement
      ? CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
      : CIContext()

    var out = Data(count: width * height * 4)
    out.withUnsafeMutableBytes { buffer in
      context.render(
        filter.outputImage!, toBitmap: buffer.baseAddress!, rowBytes: width * 4,
        bounds: CGRect(x: 0, y: 0, width: width, height: height), format: .RGBA8,
        colorSpace: noColorManagement ? nil : srgb)
    }
    result(FlutterStandardTypedData(bytes: out))
  }
}
